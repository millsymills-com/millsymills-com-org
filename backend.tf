terraform {
  backend "s3" {
    bucket       = "tfstate-millsymills-025507317036"
    key          = "millsymills-com-org/terraform.tfstate"
    region       = "us-west-1"
    use_lockfile = true
    encrypt      = true
    kms_key_id   = "alias/tfstate-millsymills"
  }
}
