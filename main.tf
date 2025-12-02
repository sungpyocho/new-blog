# ------------------------------------------------------------------------
# [1] 설정 및 공급자(Provider) 정의
# ------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 기본 리전: 서울 (S3 버킷 등을 만드는 곳)
provider "aws" {
  region = "ap-northeast-2"
}

# 버지니아 리전: CloudFront용 인증서는 '반드시' 여기서 만들어야 함 (AWS 규칙)
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# ------------------------------------------------------------------------
# [2] 변수 설정 (여기만 고치면 다른 블로그도 만들 수 있어요)
# ------------------------------------------------------------------------

variable "root_domain" {
  description = "사용할 도메인 주소"
  default     = "sungpyo.dev" 
}

variable "www_domain" {
  default = "www.sungpyo.dev" # 서브 도메인
}

variable "bucket_name" {
  description = "S3 버킷 이름 (전 세계에서 유일해야 함)"
  default     = "astroblog-sungpyodev" 
}

# ------------------------------------------------------------------------
# [3] S3 버킷 (웹사이트 파일 저장소)
# ------------------------------------------------------------------------

# 버킷 생성
resource "aws_s3_bucket" "blog_bucket" {
  bucket = var.bucket_name
}

# 보안 설정: 퍼블릭 액세스(공개 접근) 완전 차단
# "어? 차단하면 어떻게 접속해?" -> CloudFront를 통해서만 들어오게 할 겁니다.
resource "aws_s3_bucket_public_access_block" "blog_bucket_access" {
  bucket = aws_s3_bucket.blog_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# OAC 생성: CloudFront가 S3 문을 열고 들어갈 수 있는 '디지털 열쇠'
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-oac-${var.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- [인증서 (ACM)] ---
# 루트와 www 둘 다 포함하는 인증서를 만듭니다.
# SSL 인증서 (HTTPS 자물쇠) - 버지니아 리전 사용
resource "aws_acm_certificate" "cert" {
  provider                  = aws.virginia
  domain_name               = var.root_domain
  subject_alternative_names = [var.www_domain] # www도 추가
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 버킷 정책: "CloudFront(열쇠 가진 애)만 내 내용물을 볼 수 있게 해줘"
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.blog_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFront"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.blog_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------
# [4] CloudFront (CDN) - 전 세계 배포
# ------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "s3_distribution" {
  # 원본(Origin) 설정: S3와 연결
  origin {
    domain_name              = aws_s3_bucket.blog_bucket.bucket_regional_domain_name
    origin_id                = "S3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # 접속 시 보여줄 기본 파일

  # 커스텀 도메인 이름 연결
  aliases = [var.root_domain, var.www_domain]

  # 캐시 동작 설정
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.bucket_name}"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https" # http로 오면 https로 강제 이동
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # 전 세계 어디서든 접속 가능 (제한 없음)
  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  # HTTPS 인증서 연결
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ------------------------------------------------------------------------
# [6] 출력
output "NEXT_STEP" {
  value = "아래 CNAME 정보를 스퀘어스페이스에 등록하고 인증서 발급을 기다리세요."
}

output "acm_verification_record" {
  value = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
}

# CloudFront 주소가 나오면 나중에 스퀘어스페이스 ALIAS에 넣습니다.
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
