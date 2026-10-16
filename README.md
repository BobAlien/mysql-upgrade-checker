# mysql-upgrade-checker

Pre-upgrade checks for MySQL 8.0 → 8.4 (on-prem and AWS RDS).

> Status: work in progress.

## Goals
- Check target binaries and glibc compatibility
- Detect accounts using `mysql_native_password`
- Detect options removed in 8.4 in your `.cnf`
- Validate the config with `mysqld --validate-config`
- Capture a before/after baseline and compare

## Usage
_Coming soon._

## License
MIT