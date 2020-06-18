# accumulo-emr-install
Bash scripts for bootstrapping Accumulo and/or Presto on AWS EMR

 Each folder contains a different bootstrap package. The `*-bootstrap.sh` files are top level scripts called by EMR
 during cluster startup. The `-*install.sh` files install separate components. The `accumulo-backup.sh` script runs a 
 backup procedure for Accumulo.  