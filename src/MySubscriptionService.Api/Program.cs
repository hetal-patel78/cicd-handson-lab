using MySubscriptionService.Core.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<ISubscriptionService, SubscriptionService>();
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();
app.Run();

public partial class Program { }
