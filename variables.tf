variable "region" {

    default = "ap-south-1"
}

variable "project" {

    default = "zomato"
}

variable "env" {
    
    type = list
    default = ["prod", "dev"]
}

variable "domain" {

    default = "cobbtech.site"
}

variable "instance_type" {

    default = "t2.micro"
}