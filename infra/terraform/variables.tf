variable "environment" {
  description = "Deployment environment (test/uat/production)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "billing-buyflow"
}

variable "oidc_provider_id" {
  description = "EKS OIDC provider ID for IRSA"
  type        = string
}