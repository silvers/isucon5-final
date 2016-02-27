package Isucon5f::Web;

use 5.020;
use strict;
use warnings;
use utf8;
use Encode;
use Kossy;
use DBIx::Sunny;
use JSON;
use Furl::HTTP;
use URI::Escape::XS qw/uri_escape/;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use String::Util qw(trim);
use File::Basename qw(dirname);
use File::Spec;
use Cache::Isolator;
use Cache::Memcached::Fast::Safe;
my $USER_CACHE_KEY = 'users';
my $GOLANG_ENDPOINT = 'http://localhost:8083';

use constant +{
    HTTP_MINOR_VERSION => 0,
    HTTP_CODE          => 1,
    HTTP_MSG           => 2,
    HTTP_HEADERS       => 3,
    HTTP_BODY          => 4,
};

my $JSON = JSON->new;
my $UA = Furl::HTTP->new();
my $CACHE = Cache::Memcached::Fast::Safe->new({
    servers            => [ 'app3.five-final.isucon.net:11211' ],
    utf8               => 1,
    serialize_methods  => [sub { $JSON->encode(@_) }, sub { $JSON->decode(@_) }],
});
my $ISOLATOR = Cache::Isolator->new(
    cache => $CACHE,
    concurrency => 4, # get_or_setのcallbackの最大平行動作数。デフォルト1
    interval => 0.01, #lockを確認するinterval
    timeout => 10, #lockする最長時間
    trial => 0, #lockを試行する最大回数
);

my %SERVICES = map { $_->{service} => $_ } (
    {
        service => 'ken',
        meth => 'GET',
        token_type => undef,
        token_key => undef,
        uri => 'http://api.five-final.isucon.net:8082/%s'
    },
    {
        service => 'ken2',
        meth => 'GET',
        token_type => undef,
        token_key => undef,
        uri => 'http://api.five-final.isucon.net:8082/'
    },
    {
        service => 'surname',
        meth => 'GET',
        token_type => undef,
        token_key => undef,
        uri => 'http://api.five-final.isucon.net:8081/surname'
    },
    {
        service => 'givenname',
        meth => 'GET',
        token_type => undef,
        token_key => undef,
        uri => 'http://api.five-final.isucon.net:8081/givenname'
    },
    {
        service => 'tenki',
        meth => 'GET',
        token_type => 'param',
        token_key => 'zipcode',
        uri => 'http://api.five-final.isucon.net:8988/'
    },
    {
        service => 'perfectsec',
        meth => 'GET',
        token_type => 'header',
        token_key => 'X-PERFECT-SECURITY-TOKEN',
        uri => 'https://api.five-final.isucon.net:8443/tokens'
    },
    {
        service => 'perfectsec_attacked',
        meth => 'GET',
        token_type => 'header',
        token_key => 'X-PERFECT-SECURITY-TOKEN',
        uri => 'https://api.five-final.isucon.net:8443/attacked_list'
    },
);

sub endpoints {
    my ($service) = @_;
    return $SERVICES{$service};
}

sub cache_expiration {
    my ($service) = @_;
    return 86400 if ($service =~ /ken/);
    return 86400 if ($service =~ /users/);
    return 5     if ($service eq 'tenki');
    return 10; # 暫定
}

sub db {
    state $db ||= do {
        my %db = (
            host => $ENV{ISUCON5_DB_HOST} || 'db.five-final.isucon.net',
            port => $ENV{ISUCON5_DB_PORT} || 5432,
            username => $ENV{ISUCON5_DB_USER} || 'isucon',
            password => $ENV{ISUCON5_DB_PASSWORD},
            database => $ENV{ISUCON5_DB_NAME} || 'isucon5f',
        );
        DBIx::Sunny->connect(
            "dbi:Pg:dbname=$db{database};host=$db{host};port=$db{port}", $db{username}, $db{password}, {
                RaiseError => 1,
                PrintError => 0,
                AutoInactiveDestroy => 1,
            },
        );
    };
}

my ($SELF, $C);
sub session : lvalue {
    $C->req->env->{"psgix.session"};
}

sub stash {
    $C->stash;
}

sub authenticate {
    my ($email, $password) = @_;
    my $query = <<SQL;
SELECT id, email, grade FROM users WHERE email=? AND passhash=digest(salt || ?, 'sha512')
SQL
    my $user = db->select_row($query, $email, $password);
    if ($user) {
        stash->{user} = $user;
        session->{user_id} = $user->{id};
    }
    return $user;
}

sub current_user {
    my $user = stash->{user};
    return $user if $user;
    return undef if !session->{user_id};
    $user = $CACHE->get("$USER_CACHE_KEY:".session->{user_id});
    if (!$user) {
        session = +{};
    } else {
        stash->{user} = $user;
    }
    return $user;
}

my @SALT_CHARS = ('a'..'z', 'A'..'Z', '0'..'9');
sub generate_salt {
    my $salt = '';
    $salt .= $SALT_CHARS[int(rand(0+@SALT_CHARS))] for 1..32;
    $salt;
}

filter 'set_global' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        $SELF = $self;
        $C = $c;
        $app->($self, $c);
    }
};

get '/signup' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    session = +{};
    $c->render('signup.tx');
};

post '/signup' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    my $params = $c->req->parameters;
    my $email = $params->{email};
    my $password = $params->{password};
    my $grade = $params->{grade};
    my $salt = generate_salt();
    my $insert_user_query = <<SQL;
INSERT INTO users (email,salt,passhash,grade) VALUES (?,?,digest(? || ?, 'sha512'),?) RETURNING id
SQL
    my $default_arg = +{};
    my $insert_subscription_query = <<SQL;
INSERT INTO subscriptions (user_id,arg) VALUES (?,?)
SQL
    {
        my $txn = db->txn_scope;
        my $user_id = db->select_one($insert_user_query, $email, $salt, $salt, $password, $grade);
        db->query($insert_subscription_query, $user_id, $JSON->encode($default_arg));
        my $new_user = db->select_row('SELECT id,email,grade FROM users WHERE id=?', $user_id);
        $txn->commit;
        $CACHE->set("$USER_CACHE_KEY:$user_id", $new_user);
    }
    $c->redirect('/login');
};

post '/cancel' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    $c->redirect('/signup');
};

get '/login' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    session = +{};
    $c->render('login.tx');
};

post '/login' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    my $email = $c->req->param("email");
    my $password = $c->req->param("password");
    authenticate($email, $password);
    $c->halt(403) if !current_user();
    $c->redirect('/');
};

get '/logout' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    session = +{};
    $c->redirect('/login');
};

get '/' => [qw(set_global)] => sub {
    my ($self, $c) = @_;

    if (!current_user()) {
        return $c->redirect('/login');
    }
    $c->render('main.tx', { user => current_user() });
};

my $INTERVAL_MAP = +{
    micro    => 30000,
    small    => 30000,
    standard => 20000,
    premium  => 10000,
};
get '/user.js' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    $c->halt(403) if !current_user();
    my $interval = $INTERVAL_MAP->{current_user()->{grade}};

    $c->res->header('Content-Type', 'application/javascript');
    $c->res->body("var AIR_ISU_REFRESH_INTERVAL = $interval;");
};

get '/modify' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    my $user = current_user();
    $c->halt(403) if !$user;
    my $query = <<SQL;
SELECT arg FROM subscriptions WHERE user_id=?
SQL
    my $arg = db->select_one($query, $user->{id});
    $c->render('modify.tx', { user => $user, arg => $arg });
};

post '/modify' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    my $user = current_user();
    $c->halt(403) if !$user;
    my $params = $c->req->parameters;
    my $service = $params->{service} ? trim($params->{service}): undef;
    my $token = $params->{token} ? trim($params->{token}) : undef;
    my $keys = $params->{keys} ? [split(/\s+/, trim($params->{keys}))] : undef;
    my $param_name = $params->{param_name} ? trim($params->{param_name}) : undef;
    my $param_value = $params->{param_value} ? trim($params->{param_value}) : undef;
    my $select_query = <<SQL;
SELECT arg FROM subscriptions WHERE user_id=? FOR UPDATE
SQL
    my $update_query = <<SQL;
UPDATE subscriptions SET arg=? WHERE user_id=?
SQL
    {
        my $txn = db->txn_scope;
        my $arg_json = db->select_one($select_query, $user->{id});
        my $arg = $JSON->decode($arg_json);
        if (!$arg->{$service}) { $arg->{$service} = +{}; }
        if ($token) { $arg->{$service}{token} = $token; }
        if ($keys) { $arg->{$service}{keys} = $keys; }
        if ($param_name && $param_value) {
            if (!$arg->{$service}{params}) { $arg->{$service}{params} = +{}; }
            $arg->{$service}{params}{$param_name} = $param_value;
        }
        db->query($update_query, $JSON->encode($arg), $user->{id});
        $txn->commit;
    }
    $c->redirect('/modify');
};

sub _create_requests {
    my ($user_id) = @_;

    my $arg_json = db->select_one("SELECT arg FROM subscriptions WHERE user_id = ?", $user_id);
    my $arg = $JSON->decode($arg_json);

    my @requests;
    for my $service (keys %$arg) {
        my $conf = $arg->{$service};

        my $row = endpoints($service);
        my $expiration = cache_expiration($service);
        my $endpoint = sprintf $row->{uri}, @{ $conf->{keys} || [] };
        my %params = defined $conf->{params} ? %{ $conf->{params} } : ();

        my %headers;
        my $token_type = $row->{token_type};
        if (not defined $token_type) {
            # nothing to do
        }
        elsif ($token_type eq 'header') {
            my $token_key = $row->{token_key};
            $headers{$token_key} = $conf->{token};
        }
        elsif ($token_type eq 'param') {
            my $token_key = $row->{token_key};
            $params{$token_key} = $conf->{token};
        }

        if (%params) {
            $endpoint .= '?';
            for my $key (keys %params) {
                $endpoint .= uri_escape($key).'='.uri_escape($params{$key}).'&';
            }
            chop $endpoint;
        }

        my $cache_key = join '=', $endpoint, %headers;
        push @requests => {
            cache_key  => $cache_key,
            expiration => $expiration,
            service    => $service,
            headers    => \%headers,
            endpoint   => $endpoint,
        };
    }

    return @requests;
}

sub _fetch_apis_by_requests {
    my @requests = @_;
    return [] if @requests == 0;

    my @cache_keys = map { $_->{cache_key} } @requests;

    # get from cache
    my $ret = $CACHE->get_multi(@cache_keys);
    my @non_cached_requests = grep { not defined $ret->{$_->{cache_key}} } @requests;
    return [values %$ret] unless @non_cached_requests;

    # TODO: なんとかする
    # if (@non_cached_requests == 1) {
    #     return [_fetch_api_by_request($non_cached_requests[0])];
    # }

    # send request to backend
    my $body = Encode::encode_utf8($JSON->encode(\@non_cached_requests));
    my @res = $UA->post($GOLANG_ENDPOINT, ['Content-Type' => 'application/json'], $body);
    my $responses = $JSON->decode(Encode::decode_utf8($res[HTTP_BODY]));

    # set cache
    my @cache_requests;
    for my $response (@$responses) {
        my $cache_key  = delete $response->{cache_key};
        my $expiration = delete $response->{expiration};
        push @cache_requests => [$cache_key, $response, $expiration];
    }
    $CACHE->set_multi(@cache_requests);

    return [values %$ret, @$responses];
}

# XXX: なんかうまくいかない
sub _fetch_api_by_request {
    my ($request) = @_;
    return $ISOLATOR->get_or_set($request->{cache_key}, sub {
        my @res = $UA->get($request->{endpoint}, [%{$request->{headers}}]);
        return {
            service => $request->{service},
            data    => $JSON->decode(Encode::decode_utf8($res[HTTP_BODY])),
        };
    }, $request->{expiration});
}

sub fetch_apis {
    my ($user_id) = @_;
    my @requests = _create_requests($user_id);
    # TODO: なんとかする
    # return [_fetch_api_by_request(@requests)] if @requests == 1;
    return _fetch_apis_by_requests(@requests);
}

get '/data' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    my $user = current_user();
    $c->halt(403) if !$user;

    my $res = fetch_apis($user->{id});
    $c->res->header('Content-Type' => 'application/json');
    $c->res->body(Encode::encode_utf8($JSON->encode($res)));
};

get '/initialize' => sub {
    my ($self, $c) = @_;
    my $file = File::Spec->rel2abs("../../sql/initialize.sql", dirname(dirname(__FILE__)));
    system "psql",
        -h => 'db.five-final.isucon.net',
        -U => 'isucon',
        -f => $file,
        -d => "isucon5f";

    my $users = db->select_all("SELECT id,email,grade FROM users");
    my @cache_requests = map { ["$USER_CACHE_KEY:$_->{id}", $_] } @$users;
    $CACHE->set_multi(@cache_requests);

    my %seen;
    my @requests = grep { $_->{expiration} == 86400 && !$seen{$_->{cache_key}}++ } map { _create_requests($_->{id}) } @$users;
    _fetch_apis_by_requests(@requests[0..300]);

    [200];
};

1;
