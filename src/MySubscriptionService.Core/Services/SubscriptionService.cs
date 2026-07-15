using MySubscriptionService.Core.Models;

namespace MySubscriptionService.Core.Services;

public class SubscriptionService : ISubscriptionService
{
    private readonly List<Subscription> _subscriptions = new();

    public Task<Subscription> CreateSubscription(string customerName, string email, string plan, decimal amount)
    {
        var subscription = new Subscription
        {
            Id = Guid.NewGuid(),
            CustomerName = customerName,
            Email = email,
            Plan = plan,
            Amount = amount,
            CreatedAt = DateTime.UtcNow,
            IsActive = true
        };
        _subscriptions.Add(subscription);
        return Task.FromResult(subscription);
    }

    public Task<Subscription?> GetSubscription(Guid id)
    {
        var sub = _subscriptions.FirstOrDefault(s => s.Id == id);
        return Task.FromResult(sub);
    }

    public Task<IEnumerable<Subscription>> GetAllSubscriptions()
    {
        return Task.FromResult<IEnumerable<Subscription>>(_subscriptions.ToList());
    }

    public Task<bool> CancelSubscription(Guid id)
    {
        var sub = _subscriptions.FirstOrDefault(s => s.Id == id);
        if (sub == null) return Task.FromResult(false);
        sub.IsActive = false;
        return Task.FromResult(true);
    }
}
