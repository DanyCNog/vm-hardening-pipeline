variable "debian_version" {
  type    = string
  default = "13.7.0"
}

variable "iso_sha256" {
  type    = string
  default = "a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355"
}

variable "vm_name" {
  type    = string
  default = "debian13-cis"
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
