terraform {
  required_providers {
    aws = {
      version = "~> 4.20.1"
    }
  }
}


provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "my_first_ecr_repo" {
  name = "my-first-ecr-repo"
}

resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"
}

resource "aws_ecs_task_definition" "my_first_task" {
  family = "my-first-task"
  container_definitions = jsonencode([
    {
      name = "my-first-task"
      image = aws_ecr_repository.my_first_ecr_repo.repository_url
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort = 3000
        }
      ]
      memory = 512
      cpu = 256
    }
  ])
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  memory = 512
  cpu = 256
  execution_role_arn = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "my_first_service" {
  name = "my-first-service"
  cluster = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_first_task.arn
  launch_type = "FARGATE"
  desired_count = 1

  load_balancer {
    target_group_arn = "${aws_lb_target_group.example_target_group.arn}"
    container_name = "${aws_ecs_task_definition.my_first_task.family}"
    container_port = 3000
  }

  network_configuration {
    subnets = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true
    security_groups = ["${aws_security_group.service_security_group.id}"]
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_default_vpc" "default_vpc" {}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-east-1b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-east-1c"
}

resource "aws_alb" "application_load_balancer" {
  name = "test-lb-tf"
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]

  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # allow traffic in from all sources
  }

  egress {
    from_port = 0 # allowing any
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "example_target_group" {
  name = "example-target-group"
  port = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id = "${aws_default_vpc.default_vpc.id}"
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "example-listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}"
  port = "80"
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = "${aws_lb_target_group.example_target_group.arn}"
  }
}
