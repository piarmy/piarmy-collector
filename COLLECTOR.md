docker node ls
ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS
54z6afprdrp77pcnqc3f10t4v     piarmy02            Ready               Active              
nq84lfpithbbxon332kakfg2j     piarmy03            Ready               Active              
sv97z72mx5zmvpdx5npmkyh2u *   piarmy01            Ready               Active              Leader
twfqnnv7knhybbdhi8r4cmaal     piarmy04            Ready               Active     

# SSH Method
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no piarmy02 docker ps -q > data/piarmy02.containerIDs.txt