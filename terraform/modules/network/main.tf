# =============================================================================
# Network module: VPC, public + private subnets across 2 AZs, NAT GW, flow logs
# =============================================================================
# Subnetting plan (mirrors the playbook's IP-allocation table):
#
#   /16 VPC supernet                 e.g. 10.50.0.0/16
#     /20 public  AZ-a               10.50.0.0/20    (4096 IPs)
#     /20 public  AZ-b               10.50.16.0/20
#     /20 private AZ-a (apps + db)   10.50.32.0/20
#     /20 private AZ-b (apps + db)   10.50.48.0/20
#     /20 reserved for future use    10.50.64.0/20 ... etc.
# =============================================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc-${var.region_short}"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# ---------- Public subnets (one per AZ) ----------
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-snet-pub-${var.azs[count.index]}"
    Tier = "public"
  })
}

# ---------- Private subnets (apps + database live here) ----------
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 2)

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-snet-prv-${var.azs[count.index]}"
    Tier = "private"
  })
}

# ---------- NAT (single AZ to keep cost down; HA-NAT for prod) ----------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-eip-nat" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(var.tags, { Name = "${var.name_prefix}-natgw" })
  depends_on    = [aws_internet_gateway.this]
}

# ---------- Route tables ----------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rt-pub" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rt-prv" })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- VPC Flow Logs (mirrors playbook §1.7) ----------
resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = 30
  kms_key_id        = var.flow_logs_kms_arn
  tags              = var.tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.name_prefix}-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  role  = aws_iam_role.flow_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count           = var.enable_flow_logs ? 1 : 0
  log_destination = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
}
