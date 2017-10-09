## Notes

# chmod 777 -R /home/pi/images/piarmy-collector/containerFiles/data/

```
sudo nano /lib/systemd/system/collector.service
```

```
[Unit]
Description=Collector script for piarmy-collecot
After=multi-user.target

[Service]
Type=simple
User=pi
Group=pi
ExecStart=/home/pi/images/piarmy-collector/collector.sh
Restart=always
RestartSec=90
StartLimitInterval=400
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
```

```
sudo chmod 644 /lib/systemd/system/collector.service
chmod +x /home/pi/images/piarmy-collector/collector.sh
sudo systemctl daemon-reload
sudo systemctl enable collector.service
sudo systemctl start collector.service
sudo systemctl status collector
```

### When modifying script, start/stop/reload:
```
sudo systemctl stop collector.service && \
  sudo systemctl daemon-reload && \
  sudo systemctl start collector.service && \
  sudo journalctl -f -u collector.service
```