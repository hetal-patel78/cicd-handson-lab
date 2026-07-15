using MySubscriptionService.Core.Models;
using MySubscriptionService.Core.Services;
using FluentAssertions;
using Xunit;

namespace MySubscriptionService.UnitTests;

public class SubscriptionServiceTests
{
    private readonly SubscriptionService _sut;

    public SubscriptionServiceTests()
    {
        _sut = new SubscriptionService();
    }

    [Fact]
    public async Task CreateSubscription_Should_Return_Subscription_With_Correct_Values()
    {
        var result = await _sut.CreateSubscription("John Doe", "john@test.com", "Premium", 99.99m);

        result.Should().NotBeNull();
        result.CustomerName.Should().Be("John Doe");
        result.Email.Should().Be("john@test.com");
        result.Plan.Should().Be("Premium");
        result.Amount.Should().Be(99.99m);
        result.IsActive.Should().BeTrue();
    }

    [Fact]
    public async Task GetSubscription_Should_Return_Null_When_Not_Found()
    {
        var result = await _sut.GetSubscription(Guid.NewGuid());
        result.Should().BeNull();
    }

    [Fact]
    public async Task GetAllSubscriptions_Should_Return_All_Created_Subscriptions()
    {
        await _sut.CreateSubscription("Alice", "alice@test.com", "Basic", 10m);
        await _sut.CreateSubscription("Bob", "bob@test.com", "Pro", 50m);

        var all = await _sut.GetAllSubscriptions();
        all.Should().HaveCount(2);
    }

    [Fact]
    public async Task CancelSubscription_Should_Mark_As_Inactive()
    {
        var sub = await _sut.CreateSubscription("Test", "test@test.com", "Basic", 10m);
        await _sut.CancelSubscription(sub.Id);

        var cancelled = await _sut.GetSubscription(sub.Id);
        cancelled.Should().NotBeNull();
        cancelled!.IsActive.Should().BeFalse();
    }
}
