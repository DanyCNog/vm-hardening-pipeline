variable "rocky_version" {
  type    = string
  default = "10.2"
}

variable "iso_sha256" {
  type    = string
  default = "aac6ac3ce781b91a91ce78463405f66c611a5dca4b3840c79e5e01d97302f6c8"
}

variable "vm_name" {
  type    = string
  default = "rocky10-cis"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = number
  default = 20480
}

variable "headless" {
  type    = bool
  default = false
}

variable "ssh_username" {
  type    = string
  default = "labadmin"
}

variable "ssh_password" {
  type      = string
  sensitive = true
}
