using MySubscriptionService.Core.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<ISubscriptionService, SubscriptionService>();
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();

app.MapGet("/ping", () => Results.Ok(new { status = "alive" }));
app.MapGet("/ready", () => Results.Ok(new { status = "ready" }));

app.Run();

public partial class Program { }
