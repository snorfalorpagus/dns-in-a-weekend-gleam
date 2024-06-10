# Implement DNS in a weekend in Gleam

A recursive DNS resolver written in [Gleam](https://gleam.run/) based on
[Implement DNS in a weekend](https://implement-dns.wizardzines.com/). Parts 1 to 3 are complete, with some unit tests
too.

```sh
$ gleam run example.com
   Compiled in 0.00s
    Running dns_in_a_weekend_gleam.main
Querying 198.41.0.4 for example.com
Querying 192.41.162.30 for example.com
Querying 198.41.0.4 for a.iana-servers.net
Querying 192.55.83.30 for a.iana-servers.net
Querying 199.43.135.53 for a.iana-servers.net
Querying 199.43.135.53 for example.com
Answer: 93.184.215.14
```

To run the tests

```sh
$ gleam test
   Compiled in 0.00s
    Running dns_in_a_weekend_gleam_test.main
.....
Finished in 0.018 seconds
5 tests, 0 failures
```
