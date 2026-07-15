using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace MySubscriptionService.IntegrationTests;

public class SubscriptionApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public SubscriptionApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task CreateAndGetSubscription_Should_Work_EndToEnd()
    {
        var createRequest = new
        {
            CustomerName = "Integration Test User",
            Email = "integ@test.com",
            Plan = "Enterprise",
            Amount = 499.99m
        };

        var createResponse = await _client.PostAsJsonAsync("/api/subscriptions", createRequest);
        createResponse.StatusCode.Should().Be(System.Net.HttpStatusCode.Created);

        var created = await createResponse.Content.ReadFromJsonAsync<SubscriptionDto>();
        created.Should().NotBeNull();
        created!.CustomerName.Should().Be("Integration Test User");

        var getResponse = await _client.GetAsync($"/api/subscriptions/{created.Id}");
        getResponse.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);

        var fetched = await getResponse.Content.ReadFromJsonAsync<SubscriptionDto>();
        fetched.Should().NotBeNull();
        fetched!.Email.Should().Be("integ@test.com");
    }

    [Fact]
    public async Task GetAll_Should_Return_Empty_List_Initially()
    {
        var response = await _client.GetAsync("/api/subscriptions");
        response.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);

        var subscriptions = await response.Content.ReadFromJsonAsync<List<SubscriptionDto>>();
        subscriptions.Should().BeEmpty();
    }
}

public class SubscriptionDto
{
    public Guid Id { get; set; }
    public string CustomerName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Plan { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsActive { get; set; }
}
