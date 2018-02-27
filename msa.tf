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
  default = "bmxapikey"
}
variable slusername {
  description = "Your Softlayer username."
  default = "slusername"
}
variable slapikey {
  description = "Your Softlayer API Key."
  default = "slapikey"
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
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7P8Yw0vVZpUwD94mLbAhgjhGRTwwgBW1wLILfik8BiaL7psThwnelR9YcPO2FOs+u2x6SzLKe2VWVrhU/ZREmX9t5qgtB0xHP2n4gqGbDv7PU7vILSYxzQdmlHmrF0YfTTHOq0/IlogDcoAFN4jysZs26DwcCrzDcifcvjkGs29vZZcpkJBZeRzufqP4+MiP0u7BckXGL3dbyRyoaWEy2hgk+n9cqDoE57WMKUkA357q945N6/HFeLvd6J2YQzI+64riBIg3I03xTbFZJ/T0VXNCk530CBalW453hP9sXdtBktuu1MHawtmt8VldqMVSp7ZXsz25KNjgZtAfC7oUV"
}

variable "cos_token" {
  description = "IAM Token to access COS"
  default = "empty"
}

variable "db2pw" {
  description = "DB2_ADMIN_PWD"
  default     = "SalainenW0rd!"
}

variable "bigfix_var1" {
  description = "Variable 1 for BigFix installation"
  default     = "value1"
}

variable "bigfix_var2" {
  description = "Variable 2 for BigFix installation"
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
  os_reference_code        = "REDHAT_7_64"
  domain                   = "bigfix95.com"
  datacenter               = "${var.datacenter}"
  network_speed            = 10
  hourly_billing           = true
  private_network_only     = false
  cores                    = 2
  memory                   = 16384
  disks                    = [100]
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

  # Execute curl to ACCESS COS ... download BigFix binary package
  provisioner "remote-exec" {
  inline = [
    "curl -k \"https://s3.eu-gb.objectstorage.softlayer.net/bigfixbbucket/BigFix_Pltfrm_Install_V95_Lnx_DB2.tgz?AWSAccessKeyId=06690a231ffd44ab980fed5be88e86eb&Expires=1529632988&Signature=hHzg%2FtZzauXOX2LZZCQVWAZ4VnM%3D\" --output bigfix95.tgz",
  ]
  }

  # Generate bigfix installation responsefile on the fly
    provisioner "file" {
    content = <<EOF
##BIGFIX GENERATED RESPONSE FILE
LA_ACCEPT="true"
IS_EVALUATION="true"
CREDENTIAL_USER_FIRSTNAME="John"
CREDENTIAL_USER_LASTNAME="Smith"
CREDENTIAL_EMAIL="john.smith@mydomain.com"
CREDENTIAL_ORG="IBM US"
SRV_DNS_NAME="DNSHOST.mydomain.com"
BES_SERVER_PORT="52311"
WR_WWW_PORT="8080"
CONF_FIREWALL="no"
INSTALL_DB2="yes"
DB2_ADMIN_USER="db2inst111"
DB2_ADMIN_PWD="${var.db2pw}"
DB2_PORT="50000"
DB2_USERS_PWD="${var.db2pw}"
BES_LIC_FOLDER="/opt/iemlic"
USE_PROXY="false"
ADV_PROXY_DEFAULT="false"
PROXY_USER="none"
PROXY_HOST="PROXYHOST.mydomain.com"
PROXY_PORT="3128"
PROXY_METH="all"
TEST_PROXY="nofips"
PVK_KEY_SIZE="min"
IS_SILENT="TRUE"

EOF
	destination = "/root/bigfixresponsefile"
  }
  
  # Execute the script remotely: unpack BigFix tarball, install required linux packages
  provisioner "remote-exec" {
  inline = [
#    "cd /tmp; tar -xvf  bigfix.tar.gz; chmod +x /tmp/installation.sh; sudo bash /tmp/installation.sh –f bigfixresponsefile –opt   BES_GATHER_INTERVAL=$(var.bigfix_var1) –opt BES_CERT_FILE=$(var.bigfix_var2)",
#     "tar -xvf  bigfix.tar.gz; chmod +x /tmp/installation.sh; sudo bash /tmp/installation.sh –f bigfixresponsefile",
      "tar -xvf  bigfix95.tgz",
	  "yum install -y fontconfig.x86_64 libXext.x86_64 libXrender.x86_64 libpng12.x86_64 pam.i686 libstdc++.i686 libaio",
	  "cd /root/ServerInstaller_9.5.8.38-rhe6.x86_64",
	  "./install.sh -f /root/bigfixresponsefile",
  ]
  }
  

}

#########################################################
# Output
#########################################################
output "The IP address of the VM with BigFix installed" {
  value = "${ibm_compute_vm_instance.softlayer_virtual_guest.ipv4_address}"
}