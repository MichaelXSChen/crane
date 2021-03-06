# Setups for Apache
app="httpd"                                           # app name appears in process list
xtern=0                                               # 1 use xtern, 0 otherwise.
msmr_root_client="/home/ruigu/Workspace/m-smr"        # root dir for m-smr
msmr_root_server="/home/ruigu/SSD/m-smr"
input_url="127.0.0.1"                                 # url for client to query

client_cmd="${msmr_root_client}/apps/apache/install/bin/ab -n 10 -c 10 http://128.59.17.171:9000/"
                                                      # command to start the clients
server_cmd="'${msmr_root_server}/apps/apache/install/bin/apachectl -f ${msmr_root_server}/apps/apache/install/conf/httpd.conf -k start '"
                                                      # command to start the real server
