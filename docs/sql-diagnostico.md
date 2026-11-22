# Parte 1: diagnóstico y optimización SQL

Este documento cubre los seis puntos de la Parte 1: la medición del procedimiento actual, los problemas que tiene, los cambios aplicados, las consultas para la API, la medición posterior y cómo se mantienen al día las estructuras pre-calculadas.

> **Entorno de medición.** SQL Server 2022 Developer en Docker (Docker Desktop sobre Mac con Apple Silicon, 8 GB asignados a Docker). La salida completa está en `docs/mediciones/antes.txt` y `docs/mediciones/despues.txt`. Los resultados coinciden al decimal con los que calcula `scripts/valores_esperados.py`, que reproduce el generador de datos en Python.

## Cómo reproducir

```bash
docker compose up -d sqlserver db-init      # base con los datos, sin migraciones
docker compose logs -f db-init              # esperar "Base FinPerf lista."
scripts/medir.sh antes                      # -> docs/mediciones/antes.txt
docker compose up db-migrate                # aplica db/migrations/
scripts/medir.sh despues                    # -> docs/mediciones/despues.txt
python3 scripts/valores_esperados.py 7 2023-08-15   # cifras de referencia
```

El plan de ejecución real se captura en SSMS o Azure Data Studio con *Include Actual Execution Plan* sobre el mismo `EXEC dbo.usp_GetPerformance_Legacy @PortfolioId = 7, @Year = 2023;` (después de las migraciones el procedimiento original queda con ese nombre).

## 1. Medición del procedimiento actual

Tamaño de los datos: 20 portafolios × 100 instrumentos × 2.609 días hábiles = **5.218.000 filas** en `dbo.PositionDaily`. Cada fila ocupa unos 80 bytes, así que la tabla tiene del orden de **52.000 páginas (~400 MB)**.

`EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;` con `SET STATISTICS IO, TIME ON`:

| | Caché fría | Caché caliente |
|---|---|---|
| Resultado 1 (por mes): tiempo | **33,6 s** (CPU 97,8 s) | **28,8 s** (CPU 85,2 s) |
| Resultado 1: lecturas lógicas `PositionDaily` | 154.526 (23 recorridos) | 154.526 |
| Resultado 1: lecturas lógicas `Worktable` | **16.145.550** (780 recorridos) | 16.145.550 |
| Resultado 2 (YTD): tiempo | 2,4 s | 0,5 s |
| Resultado 2: lecturas lógicas `PositionDaily` | 51.508 (recorrido completo) | 51.816 |
| **Total del procedimiento** | **36,7 s** | **29,4 s** |

`PositionDaily` ocupa ~51.500 páginas (~400 MB): cada lectura de 51.500 páginas es un recorrido completo de la tabla. Como antes de los cambios el único índice es la PK, todos los accesos son Clustered Index Scan, y el plan es paralelo (por eso el CPU es ~3 veces el tiempo transcurrido). La función está marcada como inlineable (`is_inlineable = 1`, nivel de compatibilidad 160), pero aun así el costo está en las tablas de trabajo: los 780 recorridos de `Worktable` (3 por cada uno de los 260 días del año) suman 16 millones de lecturas, que es lo que cuesta evaluar el retorno día por día. El plan de ejecución real se puede ver en SSMS o Azure Data Studio con *Include Actual Execution Plan*.

## 2. Problemas encontrados

### Corrección del cálculo

| # | Problema | Dónde | Efecto |
|---|---|---|---|
| C1 | **`RetornoYTD` suma los retornos de los instrumentos.** `SUM(DailyReturn)` sobre las filas del año mezcla dos errores: promedia (en realidad suma) instrumentos sin ponderar por tamaño (idea 3) y suma días en vez de componerlos (idea 4). | 2º resultado del procedimiento | Portafolio 7, 2023: devuelve **+613,14 %** cuando lo correcto es **+5,33 %**. Suma 26.000 retornos (100 instrumentos × 260 días). |
| C2 | **`RetornoMes` suma los retornos diarios** en vez de componerlos: `SUM(fn_PortfolioDailyReturn(...))`. | 1er resultado | Error pequeño en un mes con retornos chicos, pero crece con la volatilidad y el largo del periodo. Es el mismo error que dar 0 % para [+10 %, −10 %] en vez de −1 %. |
| C3 | **División en `DECIMAL` que trunca la precisión.** `SUM(PnL) / SUM(MarketValueBegin)` divide dos `DECIMAL(38,4)`; SQL Server deja el resultado con **6 decimales**. Un retorno diario de 0,0123456 % (0,000123456) queda en 0,000123: se pierde todo lo que va después del cuarto decimal del porcentaje. | `fn_PortfolioDailyReturn` | Sumado a C2, marzo de 2023 queda en +0,9901 % contra +0,9938 % correcto. Se corrige dividiendo en `FLOAT`. |
| C4 | **Sin protección ante división por cero o días sin datos.** Si `SUM(MarketValueBegin)` es 0, la función falla (error 8134) y tumba toda la consulta. | `fn_PortfolioDailyReturn` | Error en tiempo de ejecución. Se corrige devolviendo `NULL` y tratándolo como "sin retorno" ese día. |
| C5 | **`LOG(1 + r)` no está definido si r ≤ −100 %.** No pasa con estos datos, pero es un caso que la solución nueva tiene que contemplar. | (solución nueva) | Se guarda `LogReturn = NULL` y el día no aporta al acumulado. |

Verificación de la idea 1: la regla `PnL = MarketValueEnd − MarketValueBegin − NetFlows` **se cumple en todas las filas** (0 filas fuera de una tolerancia de 0,0001; la consulta está en `db/bench/01_antes.sql`). El P&L, por lo tanto, se puede sumar directamente y `PnLMes`/`PnLYTD` del procedimiento original están bien calculados (solo son lentos).

Supuesto: los aportes y retiros (`NetFlows`) ocurren al cierre del día. Así lo genera el script (`MVE = MVB × (1 + r) + flujo`), y por eso el retorno del día es `PnL / MVB` sin ajustar el denominador por flujos.

### Rendimiento

| # | Problema | Efecto |
|---|---|---|
| R1 | **No hay índice para los filtros reales.** El único índice es la PK sobre `PositionDailyId` (IDENTITY), que no sirve para buscar por portafolio ni por fecha. | Toda consulta recorre las 5,2 M de filas. |
| R2 | **Predicados no sargables.** `CONVERT(VARCHAR(10), AsOfDate, 120) = ...`, `YEAR(AsOfDate) = @Year` y `MONTH(AsOfDate) = d.Mes` aplican una función a la columna, así que ni siquiera con un índice se podría buscar por rango. | Obliga a evaluar la función fila por fila. |
| R3 | **Función escalar ejecutada una vez por día.** `fn_PortfolioDailyReturn` se llama ~260 veces por año consultado, y cada llamada hace su propio recorrido. Las funciones escalares además impiden paralelismo cuando no se inlinean. | Multiplica el costo por la cantidad de días. |
| R4 | **Subconsulta correlacionada por mes** para `PnLMes`, que repite el filtro no sargable. | Un recorrido adicional por mes (o un spool). |
| R5 | **Se recalcula todo desde el detalle en cada consulta.** Para un resultado por portafolio y día se agregan 100 filas de instrumentos cada vez; un ITD agregaría ~260.000 filas por consulta. | El costo crece con el largo del rango. |
| R6 | **`AsOfDate` es `DATETIME`** cuando el dato es una fecha. Ocupa 8 bytes en vez de 3, admite horas que no deberían existir y empuja a usar `CONVERT`/`CAST` para comparar por día (R2). | Más espacio y consultas más frágiles. |
| R7 | **El procedimiento no tiene `SET NOCOUNT ON`.** | Menor; mensajes de filas afectadas extra hacia el cliente. |

## 3. Cambios aplicados (`db/migrations/`)

Los scripts se aplican en orden con `db/migrate.sh` (servicio `db-migrate` de docker-compose), que registra cada uno en `dbo.SchemaMigration` para no repetirlo. El script `01_schema_y_datos.sql` no se modificó.

| Script | Cambio | Por qué |
|---|---|---|
| `001_indice_positiondaily.sql` | Índice nonclustered `(PortfolioId, AsOfDate) INCLUDE (MVB, NetFlows, PnL, MVE)` con compresión de página. | Resuelve R1. Permite agregar un portafolio desde una fecha con un seek y sin volver a la tabla base. Lo usa el refresco incremental. No se cambió el clustered para no reescribir la tabla en producción ni romper a quien dependa de `PositionDailyId`. |
| `002_tabla_portfoliodaily.sql` | Tabla `dbo.PortfolioDaily`: una fila por portafolio y día (~52 mil filas) con los totales del día, el retorno del portafolio y tres acumulados: `CumLogReturn = Σ LOG(1+r)`, `CumPnL` y `DayNumber`. Clave clustered `(PortfolioId, AsOfDate)` con `AsOfDate DATE`. | Resuelve R5 y R6 para las lecturas. La idea 3 (sumar y después dividir) se aplica una sola vez al cargar. Los acumulados convierten la composición (idea 4) en una resta: **cualquier rango se resuelve con dos lecturas puntuales**, sin importar si es MTD o ITD. |
| `003_refresco_portfoliodaily.sql` | Procedimiento `dbo.usp_RefreshPortfolioDaily @PortfolioId, @FromDate` y la carga inicial. | Mantiene la tabla al día (ver punto 6). Divide en `FLOAT` (C3), protege la división por cero (C4) y el logaritmo (C5). |
| `004_consultas_api.sql` | Vista `vw_PortfolioInfo` y funciones inline `tvf_PerformanceRange`, `tvf_PerformanceSummary`, `tvf_PerformanceMonthly`. | Las consultas del punto 4. |
| `005_reemplazo_usp_getperformance.sql` | Reescribe `dbo.usp_GetPerformance` con el mismo contrato (mismos parámetros y columnas) y el cálculo correcto. El original queda como `usp_GetPerformance_Legacy`. | La pantalla Razor actual sigue funcionando mientras se migra a React, pero ya con números correctos y rápidos. |

Alternativas consideradas:

- **Cambiar `AsOfDate` a `DATE` en la tabla de hechos.** Es lo correcto a largo plazo, pero reescribe 5,2 M de filas y puede romper a otros consumidores. Como todas las lecturas pasan a `PortfolioDaily` (que ya usa `DATE`), se deja como recomendación para una ventana de mantenimiento.
- **Vista indexada en vez de tabla.** Una vista indexada con `SUM` y `COUNT_BIG` mantendría los totales diarios sola, pero no admite funciones de ventana, así que no puede guardar los acumulados, que son lo que hace O(1) a los rangos. Además agrega costo a cada escritura en la tabla de hechos.
- **Columnstore sobre `PositionDaily`.** Aceleraría mucho las agregaciones ad hoc, pero no hace falta para estas consultas una vez que existe la tabla pre-agregada.

## 4. Consultas para la API

Todas están en `db/migrations/004_consultas_api.sql` y leen solo `dbo.PortfolioDaily` por su clave clustered. Los rangos son inclusivos en los dos extremos y operan sobre los días con datos.

**(a) Resumen a una fecha de corte**: `dbo.tvf_PerformanceSummary(@PortfolioId, @AsOf)` devuelve una fila por periodo (MTD, QTD, YTD, ITD). Calcula la fecha de inicio de cada periodo (acotada a la fecha de inicio del portafolio) y llama a la función de rango.

```sql
SELECT Period, FromDate, ToDate, DaysWithData, SumLogReturn, [Return], PnL
FROM dbo.tvf_PerformanceSummary(7, '2023-08-15')
ORDER BY SortOrder;
```

**(b) Acumulado de un rango**: `dbo.tvf_PerformanceRange(@PortfolioId, @From, @To)`. Busca el último día con datos dentro del rango y el último día anterior al rango, y resta los acumulados:

```
Retorno = EXP(CumLogReturn[fin] − CumLogReturn[antes del inicio]) − 1
P&L     = CumPnL[fin] − CumPnL[antes del inicio]
Días    = DayNumber[fin] − DayNumber[antes del inicio]
```

**(c) Retorno y P&L por mes**: `dbo.tvf_PerformanceMonthly(@PortfolioId, @From, @To)` agrupa por año y mes los días del rango (como mucho ~2.600 filas contiguas) y compone con `EXP(SUM(LogReturn)) − 1`. Los meses de los extremos se recortan al rango pedido.

Las funciones devuelven `SumLogReturn` y también `[Return]`. La API lee `SumLogReturn` y hace la conversión a retorno en C# (`FinPerf.Domain.Compounding`), donde la lógica está aislada y cubierta con los casos de control.

### Valores esperados (portafolio 7, corte 15-08-2023)

Medidos en SQL Server después de las migraciones; coinciden con `scripts/valores_esperados.py`:

| Periodo | Desde | Días | Retorno | P&L |
|---|---|---|---|---|
| MTD | 01-08-2023 | 11 | +0,1953 % | $106.817,87 |
| QTD | 01-07-2023 | 32 | +0,5654 % | $299.911,45 |
| YTD | 01-01-2023 | 162 | +2,4133 % | $1.343.330,95 |
| ITD | 01-01-2015 | 2.249 | +53,0492 % | $23.613.371,97 |

Año 2023 completo, procedimiento original contra el corregido:

| | Original | Corregido |
|---|---|---|
| RetornoYTD | +613,1420 % | **+5,3264 %** |
| PnLYTD | $2.856.350,87 | $2.856.350,87 |
| RetornoMes de marzo | +0,9901 % | **+0,9938 %** |
| RetornoMes de diciembre | +1,2753 % | **+1,2819 %** |

## 5. Medición después de los cambios

Salida completa en `docs/mediciones/despues.txt`. Tiempos de ejecución (sin compilación), portafolio 7:

| Consulta | Lecturas lógicas | Tiempo |
|---|---|---|
| (a) Resumen MTD/QTD/YTD/ITD al 15-08-2023 | 24 (`PortfolioDaily`) + 2 (`Portfolio`) | 26 ms la primera vez, **1 ms** después |
| (b) Rango 01-03-2018 a 15-08-2023 | 9 | **< 1 ms** |
| (c) Mensual 2015–2024 (120 meses) | 34 | **13 ms** |
| `usp_GetPerformance` nuevo (2023) | 7 + 6 | **3 ms** |

Comparado con el procedimiento original (mismo portafolio y año):

| | Antes | Después | Mejora |
|---|---|---|---|
| Tiempo | 29,4 s (caliente) | 3 ms | ~10.000 veces |
| Lecturas lógicas | ~16,35 millones | 13 | ~1 millón de veces |
| RetornoYTD | +613,14 % (incorrecto) | +5,33 % | |

Todas las consultas quedan muy por debajo del objetivo de 200 ms. La compilación de cada consulta la primera vez toma entre 5 y 20 ms, y después se reutiliza el plan. El mismo script incluye un control que confirma que el YTD por acumulados es igual a componer los retornos día a día (+5,3264 % en ambos) y que el P&L coincide con el de la tabla de hechos ($2.856.350,8692).

Llamadas a la API medidas con `curl` contra la base real: entre 2 y 20 ms por respuesta, incluida la red local.

El costo se traslada a la carga: aplicar las cinco migraciones, incluido crear el índice sobre 5,2 M de filas y la carga inicial de `PortfolioDaily`, tomó ~20 s en total. Cada refresco posterior toca solo un portafolio desde la fecha que cambió.

## 6. Cómo se mantienen al día las estructuras pre-calculadas

`dbo.PortfolioDaily` depende de `dbo.PositionDaily`, y sus acumulados dependen de todos los días anteriores. Por eso la regla es: **cuando cambia el día D de un portafolio, se recalculan ese día y todos los siguientes de ese portafolio**.

- **Llega un día nuevo** (caso diario): el proceso de carga, al terminar de insertar las posiciones del día, ejecuta `EXEC dbo.usp_RefreshPortfolioDaily @PortfolioId = @p, @FromDate = @dia;`. Agrega 100 filas, parte del acumulado del día anterior e inserta una fila. Es instantáneo.
- **Se corrige un día pasado**: el mismo procedimiento con la fecha corregida. Borra y recalcula desde esa fecha hasta hoy. Un portafolio tiene como mucho ~2.600 días, así que incluso corregir 2015 reescribe unas 2.600 filas pequeñas: milisegundos. No hace falta un algoritmo incremental más fino (por ejemplo, sumar solo el delta a los acumulados) porque el recálculo completo de la cola ya es barato y es más difícil de equivocarse.
- **Atomicidad**: el borrado y la inserción van en una sola transacción, así que un lector nunca ve el portafolio a medio recalcular. Para que los lectores no se bloqueen mientras dura, se recomienda activar `READ_COMMITTED_SNAPSHOT` en la base.
- **Cómo detectar qué recalcular**: lo más simple es que el proceso de carga llame al procedimiento, porque sabe qué portafolio y qué fecha tocó. Si las correcciones pueden venir de otros lados, hay dos opciones: un trigger `AFTER INSERT, UPDATE, DELETE` en `PositionDaily` que registre `(PortfolioId, MIN(AsOfDate))` en una tabla de pendientes, y un job que cada pocos minutos la procese; o Change Tracking sobre `PositionDaily` con la misma idea. Evitaría recalcular dentro del trigger para no alargar las transacciones de carga.
- **Reconciliación**: un job nocturno puede comparar, por portafolio y mes, `SUM(PnL)` de la tabla de hechos contra `PortfolioDaily` y recalcular lo que no cuadre. Es la red de seguridad si algo se escapó.
- **Caché de la API**: si la API cachea respuestas, el mismo proceso que refresca debería invalidarlas (ver README).
