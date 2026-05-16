# datadog/monitors/main.tf
# Datadog monitors referenced in the Observability section.
# Apply separately: cd datadog/monitors && terraform apply

terraform {
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
  }
}

provider "datadog" {}  # Reads DATADOG_API_KEY and DATADOG_APP_KEY from environment

variable "environment"    { type = string; default = "prod" }
variable "notify_handle"  { type = string; description = "e.g. @pagerduty-hiive-oncall" }

locals { env = var.environment }

# 1. GraphQL 5xx Error Rate
resource "datadog_monitor" "graphql_5xx" {
  name    = "[${upper(local.env)}] GraphQL 5xx Error Rate > 1%"
  type    = "log alert"
  message = "GraphQL 5xx rate exceeded 1% for 5 minutes.\n${var.notify_handle}"
  query   = "logs(\"service:hiive status:error @http.status_code:[500 TO 599]\").index(\"*\").rollup(\"count\").last(\"5m\") > 10"

  monitor_thresholds { critical = 10; warning = 5 }
  notify_no_data      = false
  require_full_window = false
  tags = ["env:${local.env}", "severity:critical", "team:sre"]
}

# 2. DBConnection Pool Exhaustion
resource "datadog_monitor" "db_pool_exhaustion" {
  name    = "[${upper(local.env)}] DBConnection Pool Exhaustion"
  type    = "log alert"
  message = "DBConnection.ConnectionError > 5 in 1 min — pool is saturated.\n${var.notify_handle}"
  query   = "logs(\"service:hiive \\\"DBConnection.ConnectionError\\\"\").index(\"*\").rollup(\"count\").last(\"1m\") > 5"

  monitor_thresholds { critical = 5; warning = 2 }
  notify_no_data      = false
  require_full_window = false
  tags = ["env:${local.env}", "severity:critical", "team:sre"]
}

# 3. RDS CPU Utilization
resource "datadog_monitor" "rds_cpu" {
  name    = "[${upper(local.env)}] RDS CPU > 85% for 10 min"
  type    = "metric alert"
  message = "RDS CPU above 85% for 10 minutes. Risk of query degradation.\n${var.notify_handle}"
  query   = "avg(last_10m):avg:aws.rds.cpuutilization{env:${local.env}} > 85"

  monitor_thresholds  { critical = 85; warning = 70 }
  notify_no_data      = true
  no_data_timeframe   = 20
  require_full_window = true
  tags = ["env:${local.env}", "severity:critical", "team:sre"]
}

# 4. P99 GraphQL Latency
resource "datadog_monitor" "p99_latency" {
  name    = "[${upper(local.env)}] P99 GraphQL Latency > 5s"
  type    = "metric alert"
  message = "P99 GraphQL latency exceeded 5s for 5 minutes.\n${var.notify_handle}"
  query   = "percentile(last_5m):p99:trace.graphql.request{env:${local.env},service:hiive} > 5000000000"

  monitor_thresholds  { critical = 5000000000; warning = 2000000000 }
  notify_no_data      = false
  require_full_window = false
  tags = ["env:${local.env}", "severity:critical", "team:sre"]
}

# 5. Pod Crash Loop
resource "datadog_monitor" "pod_restarts" {
  name    = "[${upper(local.env)}] EKS Pod Crash Loop Detected"
  type    = "metric alert"
  message = "Pod restart count > 2 in 10 minutes in the hiive namespace.\n${var.notify_handle}"
  query   = "change(sum(last_10m),last_10m):sum:kubernetes.containers.restarts{env:${local.env},kube_namespace:hiive} by {pod_name} > 2"

  monitor_thresholds  { critical = 2; warning = 1 }
  notify_no_data      = false
  require_full_window = false
  tags = ["env:${local.env}", "severity:critical", "team:sre"]
}
