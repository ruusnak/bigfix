#################################################################
# Terraform template that will deploy an VM with BigFix server
#
# Version: 1.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2017.
#
#################################################################

#########################################################
# Define the ibmcloud provider
#########################################################
provider "ibm" {
  bluemix_api_key = "${var.bxapikey}"
  softlayer_username = "${var.slusername}"
  softlayer_api_key = "${var.slapikey}"
}

#########################################################
# Define the variables
#########################################################
variable bxapikey {
  description = "Your Bluemix API Key."
}
variable slusername {
  description = "Your Softlayer username."
}
variable slapikey {
  description = "Your Softlayer API Key."
}

variable "datacenter" {
  description = "Softlayer datacenter where infrastructure resources will be deployed"
  default = "ams01"
}

variable "hostname" {
  description = "Hostname of the virtual instance to be deployed"
  default = "bigfix1"
}

variable "public_ssh_key" {
  description = "Public SSH key used to connect to the virtual guest"
}

variable "cos_token" {
  description = "IAM Token to access COS"
  default = "eyJraWQiOiIyMDE3MTAzMC0wMDowMDowMCIsImFsZyI6IlJTMjU2In0.eyJpYW1faWQiOiJJQk1pZC0xMjAwMDBFN0tTIiwiaWQiOiJJQk1pZC0xMjAwMDBFN0tTIiwicmVhbG1pZCI6IklCTWlkIiwiaWRlbnRpZmllciI6IjEyMDAwMEU3S1MiLCJnaXZlbl9uYW1lIjoiSk9VS08iLCJmYW1pbHlfbmFtZSI6IlJVVVNLQU5FTiIsIm5hbWUiOiJKT1VLTyBSVVVTS0FORU4iLCJlbWFpbCI6ImpvdWtvLnJ1dXNrYW5lbkBmaS5pYm0uY29tIiwic3ViIjoiam91a28ucnV1c2thbmVuQGZpLmlibS5jb20iLCJhY2NvdW50Ijp7ImJzcyI6ImY2NjVhNjkyNTdhOWZiZThiOGJmMGY3N2JjMjU4YTU3IiwiaW1zIjoiMTU3MTQyNyJ9LCJpYXQiOjE1MTkzNzA0NjgsImV4cCI6MTUxOTM3NDA2OCwiaXNzIjoiaHR0cHM6Ly9pYW0uYmx1ZW1peC5uZXQvaWRlbnRpdHkiLCJncmFudF90eXBlIjoicGFzc3dvcmQiLCJzY29wZSI6Im9wZW5pZCIsImNsaWVudF9pZCI6ImJ4In0.ACLiyBm8pAyRgSYEjsBPSPxZGzIWYE_wKzDo4WuGOOiIUyd7EMkkSkZhIQgQ-8mJc7X3f3bpdASBkKj-KWVvVLXrXUX_QlU3YCF5G69lSckIrw9wSE6vyoALA6V8WoHimn4Bg8vVGGZXRdDGg6_A8rxDbXcrH1FUB74iVTsVYNkt1CetLZgMmDE8oUC14dWDU_GoNeS9GfS-LqVw4bMTA_Mr5_zB2BMj3TBjF7CSlKQQ8KXffe4RStvsaDjz8MStOz27nRMW88PAMLh7G_nLdLnmuQk9mCBwFnGrprZdKwXG3USGZpGeGwc_5zY7f9nA-cZqKZu3E_XWd0r2DUngOQ"
}

variable "bigfix_var1" {
  description = "Variable 1 for BigFix installation"
  default     = "value1"
}

variable "bigfix_var2" {
  description = "Variable 1 for BigFix installation"
  default     = "value2"
}


##############################################################
# Create public key in Devices>Manage>SSH Keys in SL console
##############################################################
resource "ibm_compute_ssh_key" "cam_public_key" {
  label      = "CAM Public Key"
  public_key = "${var.public_ssh_key}"
}

##############################################################
# Create temp public key for ssh connection
##############################################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "ibm_compute_ssh_key" "temp_public_key" {
  label      = "Temp Public Key"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

##############################################################
# Create Virtual Machine and install BigFix
##############################################################
resource "ibm_compute_vm_instance" "softlayer_virtual_guest" {
  hostname                 = "${var.hostname}"
  os_reference_code        = "CENTOS_7_64"
  domain                   = "cam.ibm.com"
  datacenter               = "${var.datacenter}"
  network_speed            = 10
  hourly_billing           = true
  private_network_only     = false
  cores                    = 1
  memory                   = 1024
  disks                    = [25]
  dedicated_acct_host_only = false
  local_disk               = false
  ssh_key_ids              = ["${ibm_compute_ssh_key.cam_public_key.id}", "${ibm_compute_ssh_key.temp_public_key.id}"]
  user_metadata            = "${file("test.txt")}"

  # Specify the ssh connection
  connection {
    user        = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.ipv4_address}"
  }
  
  # copy the bigfix binary to the server  *** TODO : Object/file storage? ***
  # provisioner "file" {
  # source      = "/files/bigfixtarball.tar.gz"
  # destination = "/tmp/bigfix.tar.gz"
  # }
  
  # copy the bigfix response file template to the server  *** TODO : Object/file storage? ***
  # provisioner "file" {
  # source      = "/files/bigfixresponsefile"
  # destination = "/tmp/bigfixresponsefile"
  # }

  # Execute the script remotely - ACCESS COS using curl
  provisioner "remote-exec" {
  inline = [
  #	"mkdir \tmp; cd \tmp",
    "curl -k \"https://s3.eu-gb.objectstorage.softlayer.net/bigfixbbucket/BigFix_Pltfrm_Install_V95_Lnx_DB2.tgz\" -H \"Authorization: Bearer ${var.cos_token}\"  --output bigfix.tgz",
  ]
  }

  # Execute the script remotely
  # provisioner "remote-exec" {
  # inline = [
  #   "tar -xvf  bigfix.tgz; chmod +x ./installation.sh; sudo bash /tmp/installation.sh –f bigfixresponsefile –opt   BES_GATHER_INTERVAL=$(var.bigfix_var1) –opt BES_CERT_FILE=$(var.bigfix_var2)",
  # ]
  # }

}

#########################################################
# Output
#########################################################
output "The IP address of the VM with NodeJs installed" {
  value = "${ibm_compute_vm_instance.softlayer_virtual_guest.ipv4_address}"
}