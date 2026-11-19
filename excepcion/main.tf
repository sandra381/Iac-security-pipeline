resource "aws_s3_bucket" "sitio_publico" {
 # checkov:skip=CKV2_AWS_6: sitio web estático público, aprobado en RIESGO-042, vence 2027-01-31
 bucket = "galileo-sitio-web"
}
