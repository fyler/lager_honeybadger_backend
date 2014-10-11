lager_honeybadger_backend
======================

Backend for [lager](http://github.com/basho/lager) to log data into [Honeybadger.io](http://honeybadger.io).

## Usage
In your _app.config_
```
...
{lager, [
    {
        handlers, [
            ...
            {lager_honeybadger_backend, [{api_key, "YOUR_API_KEY"}]}
        ]
    }
]}.
...
```
