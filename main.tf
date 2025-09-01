terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.3.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "docker" {
  registry_auth {
    address  = data.aws_ecr_authorization_token.token.proxy_endpoint
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}

# get authorization credentials to push to ecr
data "aws_ecr_authorization_token" "token" {}

# Creates the ECR repository
resource "aws_ecr_repository" "ecr_repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_images_on_push
  }
}

# Pull the docker image
resource "docker_image" "prometheus_docker" {
  name = "prom/prometheus:latest"
}

#Re-tag the image
resource "docker_tag" "prometheus_retagged" {
  source_image = docker_image.prometheus_docker.name
  target_image = "${aws_ecr_repository.ecr_repo.repository_url}:latest"
}

# push image to ecr repo
resource "docker_registry_image" "ecr_prometheus" {
  name = docker_tag.prometheus_retagged.target_image
}

# get the availability zones that are available in the selected region
data "aws_availability_zones" "available" {}

# create an ECS cluster
locals {
  region = var.region
  name   = var.ecr_cluster_name

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = var.ecs_container_name
  container_port = var.ecs_container_port

  tags = {
    Name = local.name
  }
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "6.0.6"

  cluster_name = local.name

  # Cluster capacity providers
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 100
      base   = 20
    }
  }

  services = {
    (var.ecs_service_name) = {
      cpu    = 1024
      memory = 4096

      # Container definition(s)
      container_definitions = {

        (local.container_name) = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = docker_registry_image.ecr_prometheus.name

          healthCheck = {
            command = ["CMD-SHELL", "curl -f http://localhost:${local.container_port}/health || exit 1"]
          }

          portMappings = [
            {
              name          = local.container_name
              containerPort = local.container_port
              hostPort      = local.container_port
              protocol      = "tcp"
            }
          ]

          capacity_provider_strategy = {
            ASG = {
              base              = 20
              capacity_provider = "ASG"
              weight            = 50
            }
          }

          enable_cloudwatch_logging              = true
          create_cloudwatch_log_group            = true
          cloudwatch_log_group_name              = "${local.container_name}-cloudwatch-group"
          cloudwatch_log_group_retention_in_days = 5

          # Example image used requires access to write to root filesystem
          readonlyRootFilesystem = false
          memoryReservation      = 100

          restartPolicy = {
            enabled              = true
            ignoredExitCodes     = [1]
            restartAttemptPeriod = 60
          }
        }
      }

      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["ex_ecs"].arn
          container_name   = local.container_name
          container_port   = local.container_port
        }
      }

      tasks_iam_role_name        = "${local.name}-tasks"
      tasks_iam_role_description = "tasks IAM role for ${local.name}"
      tasks_iam_role_policies = {
        ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      }
      tasks_iam_role_statements = [
        {
          actions = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
          ]
          resources = ["*"]
        }
      ]

      subnet_ids                    = module.vpc.private_subnets
      availability_zone_rebalancing = "ENABLED"
      security_group_ingress_rules = {
        alb_3000 = {
          from_port                    = local.container_port
          description                  = "Service port"
          referenced_security_group_id = module.alb.security_group_id
        }
      }
      security_group_egress_rules = {
        all = {
          cidr_ipv4   = "0.0.0.0/0"
          ip_protocol = "-1"
        }
      }
    }
  }

  tags = local.tags
}

resource "aws_service_discovery_http_namespace" "this" {
  name        = local.name
  description = "CloudMap namespace for ${local.name}"
  tags        = local.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = local.name

  load_balancer_type = "application"

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = local.container_port
      to_port     = local.container_port
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = {
    ex_http = {
      port     = local.container_port
      protocol = "HTTP"

      forward = {
        target_group_key = "ex_ecs"
      }
    }
  }

  target_groups = {
    ex_ecs = {
      backend_protocol                  = "HTTP"
      backend_port                      = local.container_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      # Theres nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
  }

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  tags = local.tags
}

module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id                     = module.vpc.vpc_id
  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      policy              = data.aws_iam_policy_document.custom_endpoint_policy.json
    },
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      policy              = data.aws_iam_policy_document.custom_endpoint_policy.json
    },
  }

  tags = local.tags
}

data "aws_iam_policy_document" "custom_endpoint_policy" {
  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpc"

      values = [module.vpc.vpc_id]
    }
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}