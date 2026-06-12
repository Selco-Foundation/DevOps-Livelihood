output "rds_postgres_address" {
  value = length(aws_db_instance.rds_postgres) > 0 ? "${aws_db_instance.rds_postgres[0].address}" : null
}

output "db_instance_endpoint" {
  value = length(aws_db_instance.rds_postgres) > 0 ? "${aws_db_instance.rds_postgres[0].endpoint}" : null
}


output "db_instance_name" {
  description = "The database name"
  value       = length(aws_db_instance.rds_postgres) > 0 ? "${aws_db_instance.rds_postgres[0].db_name}" : null
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = length(aws_db_instance.rds_postgres) > 0 ? "${aws_db_instance.rds_postgres[0].username}" : null
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = length(aws_db_instance.rds_postgres) > 0 ? "${aws_db_instance.rds_postgres[0].port}" : null
}