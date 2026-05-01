variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "engine_version" {
  type    = string
  default = "16.3"
}
variable "multi_az" {
  type    = bool
  default = false
}
variable "database_name" {
  type    = string
  default = "primes"
}
variable "master_username" {
  type    = string
  default = "prime"
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
