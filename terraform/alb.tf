# tfsec:ignore:aws-elb-alb-not-public
# This is the public ingress for the API; making it internal defeats
# its purpose. WAF is documented as a follow-up improvement.
resource "aws_lb" "main" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.app_name}-alb"
  }
}

resource "aws_lb_target_group" "api" {
  # name_prefix (capped at 6 chars by AWS) so create_before_destroy can
  # mint a new TG without colliding on the fixed name during replacements.
  name_prefix = "ptapi-"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # Faster connection draining than the 300s default speeds up rollouts.
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.app_name}-api-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP listener.
# When a certificate_arn is provided, HTTP redirects to HTTPS.
# Otherwise HTTP forwards directly so the stack remains usable before
# DNS / ACM has been wired up. HTTPS-only is the right end state.
# tfsec:ignore:aws-elb-http-not-used
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn == "" ? "forward" : "redirect"

    dynamic "redirect" {
      for_each = var.certificate_arn == "" ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.certificate_arn == "" ? aws_lb_target_group.api.arn : null
  }
}

resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == "" ? 0 : 1
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
