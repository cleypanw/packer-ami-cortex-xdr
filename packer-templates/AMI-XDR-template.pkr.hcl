# packer-templates/AMI-XDR-template.pkr.hcl

packer {
  # Spécifiez les plugins requis. Le plugin amazon est nécessaire pour AWS.
  required_plugins {
    amazon = {
      source = "github.com/hashicorp/amazon"
      version = "~> 1" # Assurez-vous que cette version est compatible avec votre version de Packer
                       # Vous pouvez vérifier la dernière version sur le registre Packer :
                       # https://developer.hashicorp.com/packer/integrations/hashicorp/amazon
    }
  }
}

# Définition des variables qui seront utilisées dans le template.
# Les valeurs seront passées via les variables d'environnement du pipeline préfixées par PKR_VAR_
variable "aws_region" {
  type = string
  description = "Région AWS où l'AMI sera construite"
}

variable "xdr_url" {
  type = string
  description = "L'URL de l'API XDR"
}

variable "distribution_id" {
  type = string
  description = "L'ID de distribution XDR"
}

variable "auth_id" {
  type = string
  description = "L'ID d'authentification XDR"
  sensitive = true # Marque cette variable comme sensible
}

variable "auth_token" {
  type = string
  description = "Le jeton d'authentification XDR"
  sensitive = true # Marque cette variable comme sensible
}

variable "xdr_tags" {
  type = string
  description = "Les balises XDR"
}

# Définition de la source de l'AMI à partir de laquelle construire (type amazon-ebs)
source "amazon-ebs" "xdr-agent" {
  region     = var.aws_region
  source_ami = "ami-0388f26d76e0472c6"  # Ubuntu 22.04 LTS officiel - eu-west-3
  instance_type = "t2.micro"
  ssh_username = "ubuntu"
  ami_name = "xdr-agent-ubuntu-{{timestamp}}"
  tags = {
    Name    = "XDR Agent Ubuntu AMI"
    OS      = "Ubuntu"
    BuiltBy = "Packer"
  }
}

# Définition du processus de construction, incluant les provisioners
build {
  # Fait référence à la source définie ci-dessus
  sources = ["source.amazon-ebs.xdr-agent"]

  # Provisioner shell pour installer l'agent XDR
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "echo \"Installation de l'agent XDR...\"",
      # Accès aux variables via les variables d'environnement injectées par Packer
      # Packer injecte automatiquement les variables définies dans le bloc 'variable'
      # et passées via PKR_VAR_ comme variables d'environnement dans le shell.
      "HEALTHCHECK_URL=\"$XDR_URL/public_api/v1/healthcheck\"",
      # Les doubles barres obliques inversées (\\) sont nécessaires en HCL pour échapper les sauts de ligne
      "health_response=$(curl --silent --location \"$HEALTHCHECK_URL\" \\",
      "  --header \"Accept: application/json\" \\",
      "  --header \"x-xdr-auth-id: $AUTH_ID\" \\",
      "  --header \"Authorization: $AUTH_TOKEN\")",
      "health_status=$(echo \"$health_response\" | jq -r '.status')",
      "if [[ \"$health_status\" != \"available\" ]]; then",
      "  echo \"Erreur de vérification de l'API. Statut: $health_status\"",
      "  exit 1",
      "fi",
      "echo \"L'API est saine. Procédure de demande d'URL de distribution...\"",
      "API_URL=\"$XDR_URL/public_api/v1/distributions/get_dist_url\"",
      "PACKAGE_TYPE=\"sh\"",
      "response=$(curl --silent --location \"$API_URL\" \\",
      "  --header \"Accept: application/json\" \\",
      "  --header \"x-xdr-auth-id: $AUTH_ID\" \\",
      "  --header \"Authorization: $AUTH_TOKEN\" \\",
      "  --header \"Content-Type: application/json\" \\",
      "  --data '{\n    \"request_data\": {\n      \"distribution_id\": \"'$DISTRIBUTION_ID'\",\n      \"package_type\": \"'$PACKAGE_TYPE'\"\n    }\n  }')",
      "distribution_url=$(echo \"$response\" | jq -r '.reply.distribution_url')",
      "if [[ -z \"$distribution_url\" || \"$distribution_url\" == \"null\" ]]; then",
      "  echo \"Échec de la récupération de l'URL de distribution à partir de la réponse.\" ",
      "  exit 1",
      "fi",
      "echo \"URL de distribution: $distribution_url\"",
      "curl --silent --location --request POST \"$distribution_url\" \\",
      "  --header 'Accept: application/json' \\",
      "  --header \"x-xdr-auth-id: $AUTH_ID\" \\",
      "  --header \"Authorization: $AUTH_TOKEN\" \\",
      "  --output /tmp/XDR-Linux.tar.gz",
      "echo \"Le résultat a été enregistré dans /tmp/XDR-Linux.tar.gz\"",
      "cd /tmp",
      "mkdir xdr",
      "mv XDR-Linux.tar.gz xdr",
      "cd xdr",
      "tar -zxvf XDR-Linux.tar.gz",
      "sudo mkdir -p /etc/panw",
      "sudo cp cortex.conf /etc/panw/",
      "sudo chmod +x *.sh",
      "./cortex-*.sh -- --endpoint-tags $XDR_TAGS",
      "sleep 10",
      "sudo rm -rf /tmp/xdr",
      "echo \"Installation de l'agent XDR terminée.\" "
    ]
    # Plus besoin du bloc environment_vars ici car Packer gère l'injection
    # des variables définies en HCL.
  }
}