using FinPerf.Api.Data;
using FinPerf.Api.Performance;

var builder = WebApplication.CreateBuilder(args);

// Cadena de conexión fuera del código: variable de entorno
// ConnectionStrings__FinPerf o `dotnet user-secrets` (ver README).
builder.Services.Configure<DatabaseOptions>(o =>
    o.ConnectionString = builder.Configuration.GetConnectionString(DatabaseOptions.ConnectionStringName) ?? string.Empty);

builder.Services.AddProblemDetails();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<IPerformanceRepository, SqlPerformanceRepository>();
builder.Services.AddSingleton<PortfolioCatalog>();

// En desarrollo la pantalla React usa el proxy de Vite; CORS queda configurable
// para cuando se sirvan por separado.
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.WithOrigins(allowedOrigins).AllowAnyHeader().WithMethods("GET")));

var app = builder.Build();

app.UseExceptionHandler();   // excepciones no controladas -> 500 con ProblemDetails
app.UseStatusCodePages();    // 404 de rutas inexistentes -> ProblemDetails
app.UseCors();

app.MapPortfolioEndpoints();
app.MapGet("/health", () => TypedResults.Ok("ok")).ExcludeFromDescription();

app.Run();

// Expuesto para WebApplicationFactory<Program> en los tests de integración.
public partial class Program;
