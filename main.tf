data "google_project" "default" {
  project_id = var.project
}

resource "google_cloud_run_service" "default" {
  name                       = var.name
  location                   = var.location
  autogenerate_revision_name = false
  project                    = data.google_project.default.project_id

  metadata {
    namespace = data.google_project.default.project_id
    labels    = var.labels
    annotations = {
      "run.googleapis.com/launch-stage" = "BETA"
      "run.googleapis.com/ingress"      = var.ingress
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].annotations["run.googleapis.com/sandbox"],
      metadata[0].annotations["serving.knative.dev/creator"],
      metadata[0].annotations["serving.knative.dev/lastModifier"],
      metadata[0].annotations["run.googleapis.com/ingress-status"],
      metadata[0].labels["cloud.googleapis.com/location"],
    ]
  }

  template {
    spec {
      container_concurrency = var.concurrency
      timeout_seconds       = var.timeout
      service_account_name  = var.service_account_email

      containers {
        image = var.image

        ports {
          container_port = var.port
        }

        resources {
          limits = {
            cpu    = "${var.cpus * 1000}m"
            memory = "${var.memory}Mi"
          }
        }

        dynamic "env" {
          for_each = var.env

          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }

    metadata {
      name   = var.percentages["green"].revision
      labels = var.labels
      annotations = merge(
        {
          "run.googleapis.com/launch-stage"       = "BETA"
          "run.googleapis.com/cloudsql-instances" = join(",", var.cloudsql_connections)
          "autoscaling.knative.dev/maxScale"      = var.max_instances
          "autoscaling.knative.dev/minScale"      = var.min_instances
        },
        var.vpc_connector_name == null ? {} : {
          "run.googleapis.com/vpc-access-connector" = var.vpc_connector_name
          "run.googleapis.com/vpc-access-egress"    = var.vpc_access_egress
        }
      )
    }
  }

  traffic {
    percent       = var.percentages["green"].percent
    revision_name = "${var.name}-${var.percentages["green"].revision}"
  }
  traffic {
    percent       = var.percentages["blue"].percent
    revision_name = "${var.name}-${var.percentages["blue"].revision}"
  }
}


resource "google_cloud_run_service_iam_member" "public_access" {
  count    = var.allow_public_access ? 1 : 0
  service  = google_cloud_run_service.default.name
  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_domain_mapping" "domains" {
  for_each = var.map_domains

  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  name     = each.value

  metadata {
    namespace = data.google_project.default.project_id
    annotations = {
      "run.googleapis.com/launch-stage" = "BETA"
    }
  }

  spec {
    route_name = google_cloud_run_service.default.name
  }

  lifecycle {
    ignore_changes = [metadata[0]]
  }
}
