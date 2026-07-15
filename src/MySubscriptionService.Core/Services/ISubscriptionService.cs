using MySubscriptionService.Core.Models;

namespace MySubscriptionService.Core.Services;

public interface ISubscriptionService
{
    Task<Subscription> CreateSubscription(string customerName, string email, string plan, decimal amount);
    Task<Subscription?> GetSubscription(Guid id);
    Task<IEnumerable<Subscription>> GetAllSubscriptions();
    Task<bool> CancelSubscription(Guid id);
}
