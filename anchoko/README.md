# ISUCON5あんちょこ

## ベンチマーク

benchサーバで以下のコマンド打てば走るようにした。
```sh
./bench.sh
```

## スロークエリログの分析

### スロークエリログを有効にする

```sql
SET GLOBAL slow_query_log = 1;
SET GLOBAL slow_query_log_file = '/tmp/mysql-slow.log';
SET GLOBAL long_query_time = 0.0;
```

### スロークエリログを無効にする

```sql
SET GLOBAL slow_query_log = 0;
```

### インデックスが効いてないような遅いクエリだけ出す

```sql
SET GLOBAL long_query_time = 10.0;
```

### 時間順に出す

```bash
sudo -H mysqldumpslow -s t /tmp/mysql-slow.log
```

### 回数順に出す

```bash
sudo -H mysqldumpslow -s c /tmp/mysql-slow.log
```

### digest
```bash
sudo -H pt-query-digest /tmp/mysql-slow.log
```

## アクセスログの分析

```bash
cat /var/log/nginx/access.log | ./logstats.pl time
cat /var/log/nginx/access.log | ./logstats.pl count
```

## ログのローテート

```bash
sudo -H ./logrotate.pl nginx /var/log/nginx/access.log
sudo -H ./logrotate.pl mysql /tmp/mysql-slow.log
```

## コンフィグテスト

```bash
sudo -H /home/isucon/nginx/sbin/nginx -t
```

## nginx

```bash
systemctl restart nginx
```

## mysql

```bash
systemctl restart mysql
```

## gzip圧縮

```bash
gzip -r js css
gzip -k index.html
```

## netstat

```bash
sudo -H netstat -tlnp
sudo -H netstat -tnp | grep ESTABLISHED
```

## lsof

```bash
sudo -H lsof -nP -i4TCP -sTCP:LISTEN
sudo -H lsof -nP -i4TCP -sTCP:ESTABLISHED
```
