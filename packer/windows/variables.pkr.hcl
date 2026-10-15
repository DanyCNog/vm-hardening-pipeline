variable "iso_path" {
  type    = string
  default = "iso/ws2025-eval.iso"
}

variable "iso_sha256" {
  type    = string
  default = "7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51"
}

variable "image_index" {
  type    = number
  default = 2
}

variable "guest_os_type" {
  type    = string
  default = "Windows2025_64"
}

variable "vm_name" {
  type    = string
  default = "ws2025-cis"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_size" {
  type    = number
  default = 61440
}

variable "headless" {
  type    = bool
  default = false
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}
