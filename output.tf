output "vpc" {
    value = data.aws_vpc.default.id
}

output "subnet" {

    value = data.aws_subnets.default
}

output "r53_records" {

    value = aws_route53_record.record[*].name

}