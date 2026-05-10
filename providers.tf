provider "github" {
  owner = var.org_name

  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = file(var.github_app_pem_file)
  }
}

provider "aws" {
  region = var.aws_region
}
