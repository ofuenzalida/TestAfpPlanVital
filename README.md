# FinPerf: rendimiento de portafolios

Solución a la prueba técnica Fullstack .NET: diagnóstico y optimización del cálculo de rendimiento en SQL Server, una Web API en ASP.NET Core 8 y una pantalla de consulta en React.

| Parte | Qué hay | Dónde |
|---|---|---|
| 1. SQL | Diagnóstico, índice, tabla pre-agregada con acumulados, consultas para la API, refresco incremental | `db/migrations/`, `docs/sql-diagnostico.md` |
| 2. API | 4 endpoints, validación con ProblemDetails, composición aislada y testeada | `src/`, `tests/` |
| 3. Pantalla | React + TypeScript (Vite), formato es-CL | `web/` |

## Requisitos

- Docker (para SQL Server 2022). En Mac con Apple Silicon, activar la emulación x86 (Rosetta) en Docker Desktop.
- .NET SDK 8
- Node.js 18 o superior

## Cómo ejecutar

### 1. Base de datos

```bash
docker compose up -d          # SQL Server + carga de datos + migraciones
docker compose logs -f db-init db-migrate
```

La primera vez, `db-init` genera las ~5,2 millones de filas (tarda varios minutos) y después `db-migrate` aplica `db/migrations/` en orden. Si la carga se interrumpe, el siguiente arranque lo detecta (la carga se marca como completa solo al final) y la rehace. Si encuentra una base sin esa marca que no es claramente una carga a medias (por ejemplo, con más filas de las esperadas o con otras tablas), no la borra: se detiene y explica el estado. Para recrearla igual: `FINPERF_RECREATE=1 docker compose up db-init`. La contraseña de `sa` se toma de la variable `SA_PASSWORD` (por defecto la del `docker-compose.yml` entregado, solo para desarrollo).

Para medir el "antes" y el "después" (ver `docs/sql-diagnostico.md`):

```bash
docker compose up -d sqlserver db-init   # sin migraciones
scripts/medir.sh antes
docker compose up db-migrate
scripts/medir.sh despues
```

### 2. API

La cadena de conexión no está en el código. Se entrega por variable de entorno o con user-secrets:

```bash
export ConnectionStrings__FinPerf="Server=localhost,1433;Database=FinPerf;User Id=sa;Password=FinPerf_Dev_2026!;TrustServerCertificate=True"
dotnet run --project src/FinPerf.Api      # http://localhost:5080
```

O bien:

```bash
dotnet user-secrets --project src/FinPerf.Api set "ConnectionStrings:FinPerf" "Server=localhost,1433;Database=FinPerf;User Id=sa;Password=...;TrustServerCertificate=True"
```

`src/FinPerf.Api/FinPerf.Api.http` tiene ejemplos de cada endpoint.

### 3. Pantalla

```bash
cd web
npm install
npm run dev        # http://localhost:5173 (redirige /api a http://localhost:5080)
```

### Tests

```bash
dotnet test          # dominio (casos de control) + integración con WebApplicationFactory
cd web && npm test   # formato es-CL, manejo de errores y grilla mensual
scripts/test-sql.sh  # tests SQL contra la base del docker-compose (pérdida total)
```

`dotnet test` necesita el SDK de .NET 8 (`global.json` lo exige; con el SDK 6 no compila). Los tests .NET y web no necesitan SQL Server: los de integración reemplazan el repositorio por uno en memoria.

Con la base levantada, `scripts/medir.sh antes|despues|comparacion` y `scripts/planes.sh` regeneran las mediciones y los planes de ejecución de `docs/mediciones/`.

## Endpoints

| Ruta | Parámetros | Respuesta |
|---|---|---|
| `GET /api/portfolios` | | Id, nombre, fecha de inicio y rango de fechas con datos |
| `GET /api/portfolios/{id}/performance/summary` | `asOf` | Retorno y P&L de MTD, QTD, YTD e ITD |
| `GET /api/portfolios/{id}/performance` | `from`, `to` | Retorno acumulado y P&L del rango |
| `GET /api/portfolios/{id}/performance/monthly` | `from`, `to` | Retorno y P&L de cada mes, más el total de cada año |

Fechas en formato `yyyy-MM-dd`. Los retornos van como fracción (`0.0241` = 2,41 %) y `null` cuando el periodo no tiene días con datos. Errores:

- **400** (`ValidationProblemDetails`, con el detalle por campo): fecha faltante o mal escrita, `from > to`, fechas fuera del rango con datos del portafolio.
- **404** (`ProblemDetails`): portafolio inexistente.
- **500** (`ProblemDetails`): error no controlado, sin detalles internos.

## Decisiones

**Tabla pre-agregada con acumulados en vez de solo índices.** Un índice sobre `(PortfolioId, AsOfDate)` en `PositionDaily` arregla los recorridos completos, pero un ITD seguiría leyendo ~260 mil filas por consulta. `dbo.PortfolioDaily` guarda una fila por portafolio y día (~52 mil en total) con `Σ LOG(1 + r)`, `Σ P&L` y un contador de días acumulados. Así cualquier rango se resuelve con dos lecturas puntuales: `EXP(Cum[fin] − Cum[antes del inicio]) − 1`. El costo es mantenerla al día, lo que se resuelve con un procedimiento que recalcula un portafolio desde la fecha que cambió (detalle en `docs/sql-diagnostico.md`, punto 6).

**Funciones inline (TVF) para las consultas.** Se pueden componer (el resumen reutiliza la de rango), reciben parámetros y el optimizador las expande dentro de la consulta. La API las llama con SQL parametrizado.

**Dapper y no EF Core.** Son cuatro consultas de solo lectura, ya escritas y afinadas en SQL. EF Core no aporta tracking, migraciones ni LINQ útiles aquí, y Dapper deja a la vista exactamente qué SQL se ejecuta. El modelo de datos se versiona con scripts SQL (`db/migrations/` + `db/migrate.sh`), que es lo que pide la prueba.

**Composición en C#, aislada.** SQL devuelve `Σ LOG(1 + r)` (que es aditivo y por eso se puede acumular e indexar) y la API lo convierte en retorno con `FinPerf.Domain.Compounding`. Esa clase concentra las reglas 3 y 4 del enunciado y está cubierta con los casos de control: [+10 %, −10 %] = −1 %, [+10 %, −10 %, +5 %] = +3,95 % y el ejemplo A/B = +0,4545 %, además de la equivalencia entre multiplicar y sumar logaritmos. El total anual de la tabla mensual se calcula componiendo los meses con `Compounding.Compound`.

**Minimal API con `TypedResults`.** Los endpoints son pocos y simples; los tipos de resultado (`Ok`, `ValidationProblem`, `ProblemHttpResult`) dejan explícitas las respuestas posibles. Todo es `async` y el `CancellationToken` de la petición llega hasta Dapper (`CommandDefinition`) y la apertura de la conexión, así que si el cliente cancela se corta la consulta.

**Caché.** Solo se cachea la lista de portafolios con su rango de fechas con datos (`PortfolioCatalog`, `IMemoryCache`), porque todas las peticiones la usan para validar y cambia como mucho una vez al día. Expira a los 5 minutos y tiene un método `Invalidate()` para vaciarla cuando se refresque `PortfolioDaily`. Los resultados de rendimiento no se cachean: cada consulta lee unas pocas páginas por clave y cachearlos solo agregaría el riesgo de mostrar datos viejos después de una corrección.

**Pantalla.** React con Vite y TypeScript, sin librerías extra. Un hook `useApi` maneja carga, error y datos y cancela la petición anterior si cambian los filtros. `StatusMessage` centraliza los mensajes de carga, error y sin datos. Los errores de la API se muestran con el texto que viene en ProblemDetails. El formato usa `Intl.NumberFormat('es-CL')`.

## Supuestos

- Los aportes y retiros (`NetFlows`) ocurren al cierre del día, como en el script de carga (`MVE = MVB × (1 + r) + flujo`). Por eso el retorno diario es `PnL / MVB`.
- Se verificó que `PnL = MVE − MVB − NetFlows` en todas las filas (`scripts/valores_esperados.py` y `db/bench/01_antes.sql`).
- Los rangos son inclusivos y operan sobre días con datos: si `from` o `to` caen en fin de semana se usan los días hábiles dentro del rango.
- Los periodos (MTD, QTD, YTD) empiezan como muy temprano en la fecha de inicio del portafolio; ITD empieza en esa fecha.
- "Fechas dentro del rango con datos" se interpreta como: `from`, `to` y `asOf` entre el primer y el último día con datos del portafolio.
- Un día con valor inicial total 0 no tiene retorno definido y no aporta a la composición (su P&L sí se suma).
- Un día con retorno de −100 % o menos es una pérdida total: el acumulado de cualquier periodo que lo contenga es −100 %.
- En la tabla mensual, los meses de los extremos se recortan al rango pedido; la pantalla pide desde el primer día con datos hasta la fecha de corte.

## Pendiente y qué haría con más tiempo

- Test de integración contra un SQL Server real (Testcontainers) que valide las funciones SQL contra `scripts/valores_esperados.py`.
- Cambiar `AsOfDate` a `DATE` en `PositionDaily` en una ventana de mantenimiento.
- Proceso automático de refresco: tabla de pendientes alimentada por trigger o Change Tracking y un job que llame a `usp_RefreshPortfolioDaily` e invalide la caché de la API.
- Activar `READ_COMMITTED_SNAPSHOT` para que el refresco no bloquee lecturas.
- OpenAPI/Swagger, logging estructurado y health check con la base.
- Dockerfiles para la API y la pantalla, para levantar todo con un solo `docker compose up`.

## Tiempo invertido

El desarrollo lo hizo un asistente de IA (Claude) bajo la dirección de Octavio, como permite la prueba. Los tiempos son de reloj, el 22-11-2026 (hora de Chile), tomados de las horas de los commits y de los mensajes de trabajo. No hay otro registro más fino. Son mucho menores que las 3,5 horas estimadas porque el asistente escribe y ejecuta el código directamente; no reflejan el tiempo que le tomaría a una persona.

| Parte | Tramo | Tiempo aproximado |
|---|---|---|
| Preparación (lectura del enunciado, repositorio) | 13:39 a 13:40 | 1 min |
| Parte 1: SQL (diagnóstico, migraciones, valores esperados) | 13:40 a 13:45 | 5 min |
| Parte 1: mediciones reales en Docker | 14:03 a 14:13 | 10 min |
| Parte 2: API y tests | 13:45 a 13:50 | 5 min |
| Parte 3: Pantalla y tests | 13:50 a 13:53 | 3 min |
| README y documentación | 13:53 a 13:54 | 1 min |
| Correcciones de la primera revisión (006, init, planes, comparación) | 16:58 a 17:19 | 21 min |
| Corrección de la segunda revisión (init ambiguo) | 17:24 a 17:35 | 11 min |
| **Total** | | **~57 min** |

Entre las 13:54 y las 14:03 se esperó a que se instalara Docker, y entre las 14:13 y las 16:58, la revisión del código. Esos tramos no se cuentan.
