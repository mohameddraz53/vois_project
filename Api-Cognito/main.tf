# ------------------------
# Cognito
# ------------------------
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.environment}"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_cognito_resource_server" "api" {
  identifier = "https://${var.project_name}.${var.environment}/api" 
  name       = "${var.project_name}-api"

  scope {
    scope_name        = "read"
    scope_description = "Read access"
  }

  scope {
    scope_name        = "write"
    scope_description = "Write access"
  }

  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = true

  # OAuth (client_credentials فقط للـ M2M)
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true

  # استخدم سكوبات الـ resource server اللي أنشأتها
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.api.identifier}/read",
    "${aws_cognito_resource_server.api.identifier}/write"
  ]

  # قَيِّم ضمن الرينج الصحيح
  access_token_validity  = 60    # 5–60 minutes
  id_token_validity      = 60    # 5–60 minutes
  refresh_token_validity = 30    # 1–3650 days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

   lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.environment}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ------------------------
# API Gateway
# ------------------------
resource "aws_apigatewayv2_api" "this" {
  name                     = "${var.project_name}-api-gateway-${var.environment}"
  protocol_type            = "HTTP"
  route_selection_expression = "$request.method $request.path"
}

# ------------------------
# VPC Link to NLB
# ------------------------
resource "aws_apigatewayv2_vpc_link" "this" {
  name       = "${var.project_name}-vpc-link"
  subnet_ids = var.subnet_ids
  security_group_ids = []
}

# ------------------------
# Integration with NLB
# ------------------------
data "aws_lb" "nlb" {
  name = "a3bc4ba12a00348ef8bc230ff6cdb7ef"  
}

data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.nlb.arn
  port              = 80
}

resource "aws_apigatewayv2_integration" "nlb" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = data.aws_lb_listener.http.arn  
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"
}
# ------------------------
# Cognito Authorizer
# ------------------------
resource "aws_apigatewayv2_authorizer" "cognito" {
  name             = "cognito-authorizer"
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    audience = [aws_cognito_user_pool_client.client.id]
  }
}

# ------------------------
# Route protected by Cognito
# ------------------------
resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.nlb.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# ------------------------
# Stage
# ------------------------
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

