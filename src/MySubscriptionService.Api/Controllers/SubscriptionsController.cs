using Microsoft.AspNetCore.Mvc;
using MySubscriptionService.Core.Models;
using MySubscriptionService.Core.Services;

namespace MySubscriptionService.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SubscriptionsController : ControllerBase
{
    private readonly ISubscriptionService _subscriptionService;

    public SubscriptionsController(ISubscriptionService subscriptionService)
    {
        _subscriptionService = subscriptionService;
    }

    [HttpPost]
    public async Task<ActionResult<Subscription>> Create([FromBody] CreateSubscriptionRequest request)
    {
        var subscription = await _subscriptionService.CreateSubscription(
            request.CustomerName, request.Email, request.Plan, request.Amount);
        return CreatedAtAction(nameof(GetById), new { id = subscription.Id }, subscription);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<Subscription>> GetById(Guid id)
    {
        var subscription = await _subscriptionService.GetSubscription(id);
        if (subscription == null) return NotFound();
        return Ok(subscription);
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<Subscription>>> GetAll()
    {
        var subscriptions = await _subscriptionService.GetAllSubscriptions();
        return Ok(subscriptions);
    }

    [HttpPost("{id:guid}/cancel")]
    public async Task<ActionResult> Cancel(Guid id)
    {
        var result = await _subscriptionService.CancelSubscription(id);
        if (!result) return NotFound();
        return NoContent();
    }
}

public class CreateSubscriptionRequest
{
    public string CustomerName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Plan { get; set; } = "Basic";
    public decimal Amount { get; set; }
}
