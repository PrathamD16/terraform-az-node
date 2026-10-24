variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "container_app_environment_name" {
  type = string
}

variable "container_app_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "container_image" {
  type = string
}

variable "target_port" {
  type = number
}

variable "tags" {
  type = map(string)
}
