# Ports from Dalli(https://github.com/mperham/dalli/blob/master/test/test_rack_session.rb)
require 'spec_helper'

describe Rack::Session::Memcached do

  let(:incrementor_proc) {
    ->(env) {
      env['rack.session']['counter'] ||= 0
      env['rack.session']['counter'] += 1
      Rack::Response.new(env['rack.session'].inspect).to_a
    }
  }

  [:drop, :renew, :defer, :skip].each do |fn|
    let("#{fn.to_s}_session".to_sym) {
      Rack::Lint.new ->(env) {
        env['rack.session.options'][fn] = true
        incrementor_proc.call(env)
      }
    }
  end
  let(:incrementor) { Rack::Lint.new incrementor_proc }
  let(:req) { Rack::MockRequest.new(Rack::Session::Memcached.new(incrementor)) }
  let(:session_match) { /#{session_key}=([0-9a-fA-F]+);/ }
  let(:session_key) { Rack::Session::Memcached::DEFAULT_OPTIONS[:key] }

  it 'connects to existing server' do
    expect{
      session = Rack::Session::Memcached.new(incrementor, namespace: 'test:rack:session')
      session.pool.set('ping', '')
    }.not_to raise_error
  end

  it 'passes options to Mamcached' do
    session = Rack::Session::Memcached.new(incrementor, namespace: 'test:rack:session')
    expect(session.pool.instance_eval{@options[:prefix_key]}).to eq 'test:rack:session'
  end

  it 'creates a new cookie' do
    res = req.get('/')
    expect(res["Set-Cookie"]).to include("#{session_key}=")
    expect(res.body).to eq '{"counter"=>1}'
  end

  it 'determins session from cookie' do
    res = req.get('/')
    cookie= res['Set-Cookie']
    expect(req.get('/', 'HTTP_COOKIE' => cookie).body).to eq '{"counter"=>2}'
    expect(req.get('/', 'HTTP_COOKIE' => cookie).body).to eq '{"counter"=>3}'
  end

  it 'determins session only from a cookie by default' do
    res = req.get('/')
    sid = res['Set-Cookie'][session_match, 1]
    expect(req.get("/?rack.session=#{sid}").body).to eq '{"counter"=>1}'
    expect(req.get("/?rack.session=#{sid}").body).to eq '{"counter"=>1}'
  end

  it 'determins session from params' do
    req = Rack::MockRequest.new(
      Rack::Session::Memcached.new(incrementor, cookie_only: false)
    )
    res = req.get('/')
    sid = res['Set-Cookie'][session_match, 1]
    expect(req.get("/?rack.session=#{sid}").body).to eq '{"counter"=>2}'
    expect(req.get("/?rack.session=#{sid}").body).to eq '{"counter"=>3}'
  end

  it 'survives nonexistant cookies' do
    bad_cookie = 'rack.session=blahblahblah'
    res = req.get('/', 'HTTP_COOKIE' => bad_cookie)
    expect(res.body).to eq '{"counter"=>1}'
    expect(res['Set-Cookie'][session_match]).not_to match /#{bad_cookie}/
  end

  it 'survives nonexistant blank cookies' do
    bad_cookie = 'rack.session='
    res = req.get('/', 'HTTP_COOKIE' => bad_cookie)
    expect(res.body).to eq '{"counter"=>1}'
    expect(res['Set-Cookie'][session_match]).not_to match /#{bad_cookie}$/
  end

  it 'maintains freshness' do
    req = Rack::MockRequest.new(
      Rack::Session::Memcached.new(incrementor, expire_after: 3)
    )
    res = req.get('/')
    expect(res.body).to eq '{"counter"=>1}'
    cookie = res['Set-Cookie']
    res = req.get('/', 'HTTP_COOKIE' => cookie)
    expect(res.body).to eq '{"counter"=>2}'
    sleep 4
    res = req.get('/', 'HTTP_COOKIE' => cookie)
    expect(res.body).to eq '{"counter"=>1}'
  end

  it 'does not send the same session id if it did not change' do
    res0 = req.get('/')
    cookie = res0['Set-Cookie'][session_match]
    expect(res0.body).to eq '{"counter"=>1}'

    res1 = req.get('/', 'HTTP_COOKIE' => cookie)
    expect(res1['Set-Cookie']).to be nil
    expect(res1.body).to eq '{"counter"=>2}'

    res2 = req.get('/', 'HTTP_COOKIE' => cookie)
    expect(res2['Set-Cookie']).to be nil
    expect(res2.body).to eq '{"counter"=>3}'
  end

  it 'deletes cookies with :drop option' do
    rsm = Rack::Session::Memcached.new(incrementor)
    req = Rack::MockRequest.new(rsm)
    drop = Rack::Utils::Context.new(rsm, drop_session)
    dreq = Rack::MockRequest.new(drop)

    res1 = req.get('/')
    session = (cookie = res1['Set-Cookie'])[session_match]
    expect(res1.body).to eq '{"counter"=>1}'

    res2 = dreq.get('/', 'HTTP_COOKIE' => cookie)
    expect(res2['Set-Cookie']).to be nil
    expect(res2.body).to eq '{"counter"=>2}'

    res3 = req.get('/', 'HTTP_COOKIE' => cookie)
    expect(res3['Set-Cookie'][session_match]).not_to eq session
    expect(res3.body).to eq '{"counter"=>1}'
  end

  it 'provides new session id with :renew option' do
    rsm = Rack::Session::Memcached.new(incrementor)
    req = Rack::MockRequest.new(rsm)
    renew = Rack::Utils::Context.new(rsm, renew_session)
    rreq = Rack::MockRequest.new(renew)

    res1 = req.get('/')
    session = (cookie = res1['Set-Cookie'])[session_match]
    expect(res1.body).to eq '{"counter"=>1}'

    res2 = rreq.get('/', 'HTTP_COOKIE' => cookie)
    new_cookie = res2['Set-Cookie']
    new_session = new_cookie[session_match]
    expect(new_session).not_to eq session
    expect(res2.body).to eq '{"counter"=>2}'

    res3 = req.get('/', 'HTTP_COOKIE' => new_cookie)
    expect(res3.body).to eq '{"counter"=>3}'

    # Old cookie was deleted
    res4 = req.get('/', 'HTTP_COOKIE' => cookie)
    expect(res4.body).to eq '{"counter"=>1}'
  end

  it 'omits cookie with :defer option but still updates the state' do
    rsm = Rack::Session::Memcached.new(incrementor)
    count = Rack::Utils::Context.new(rsm, incrementor)
    defer = Rack::Utils::Context.new(rsm, defer_session)
    dreq = Rack::MockRequest.new(defer)
    creq = Rack::MockRequest.new(count)

    res0 = dreq.get('/')
    expect(res0['Set-Cookie']).to be nil
    expect(res0.body).to eq '{"counter"=>1}'

    res0 = creq.get('/')
    res1 = dreq.get('/', 'HTTP_COOKIE' => res0['Set-Cookie'])
    expect(res1.body).to eq '{"counter"=>2}'
    res2 = dreq.get('/', 'HTTP_COOKIE' => res0['Set-Cookie'])
    expect(res2.body).to eq '{"counter"=>3}'
  end

  it 'omits cookie and state update with :skip option' do
    rsm = Rack::Session::Memcached.new(incrementor)
    count = Rack::Utils::Context.new(rsm, incrementor)
    skip = Rack::Utils::Context.new(rsm, skip_session)
    sreq = Rack::MockRequest.new(skip)
    creq = Rack::MockRequest.new(count)

    res0 = sreq.get('/')
    expect(res0['Set-Cookie']).to be nil
    expect(res0.body).to eq '{"counter"=>1}'

    res0 = creq.get('/')
    res1 = sreq.get('/', 'HTTP_COOKIE' => res0['Set-Cookie'])
    expect(res1.body).to eq '{"counter"=>2}'
    res2 = sreq.get('/', 'HTTP_COOKIE' => res0['Set-Cookie'])
    expect(res2.body).to eq '{"counter"=>2}'
  end

  it 'updates deep hashes correctly' do
    hash_check = ->(env) {
      session = env['rack.session']
      unless session.include? 'test'
        session.update a: :b, c: {d: :e}, f: {g: {h: :i}}, 'test' => true
      else
        session[:f][:g][:h] = :j
      end
      [200, {}, [session.inspect]]
    }
    rsm = Rack::Session::Memcached.new(hash_check)
    req = Rack::MockRequest.new(rsm)

    res0 = req.get('/')
    session_id = (cookie = res0['Set-Cookie'])[session_match, 1]

    ses0 = rsm.safe_get(session_id, true)

    req.get('/', 'HTTP_COOKIE' => cookie)
    ses1 = rsm.safe_get(session_id, true)

    expect(ses1).not_to eq ses0
  end

  # on Dalli, this test is incoherent.
  it 'cleanly merges sessions when multithreaded', multithread: true do

    rsm = Rack::Session::Memcached.new(incrementor)
    req = Rack::MockRequest.new(rsm)
    res = req.get('/')
    expect(res.body).to eq '{"counter"=>1}'
    cookie = res['Set-Cookie']
    session_id = cookie[session_match, 1]

    #delta_incrementor = ->(env) {
    #  env['rack.session'] = env['rack.session'].dup
    #  Thread.stop
    #  env['rack.session'][(Time.now.usec * rand).to_i] = true
    #  incrementor.call(env)
    #}

    #tnum = rand(7).to_i + 5
    #r = Array.new(tnum) do
    #  t = Thread.new do
    #    tses = Rack::Utils::Context.new(rsm.clone, delta_incrementor)
    #    treq = Rack::MockRequest.new(tses)
    #    treq.get('/', 'HTTP_COOKIE' => cookie, 'rack.multithread' => true)
    #  end
    #  p t #dummy output
    #  t
    ## FIXME: sometime failed on this wakeup. why??
    #end.reverse.map{|t| t.wakeup.join.value}
    #r.each.with_index(2) do |res, i|
    #  expect(res.body).to include "\"counter\"=>#{i}"
    #end

    #session = rsm.safe_get(session_id)
    #expect(session.size).to be (tnum + 1)
    #expect(session['counter']).to be (tnum + 1)

    start_at = Time.now
    time_delta = ->(env) {
      delta = Time.now - start_at
      env['rack.session']['time_delta'] = delta
      [200, {'Content-Type' => 'text/plain'}, delta.to_s]
    }
    tnum = rand(7).to_i + 5
    r = Array.new(tnum) do |i|
      app = Rack::Utils::Context.new(rsm, time_delta)
      req = Rack::MockRequest.new(app)
      Thread.new(req) do |run|
        run.get('/', 'HTTP_COOKIE' => cookie, 'rack.multithread' => true)
      end.join.value
    end.reverse
    r.each do |res|
      expect(res.body.to_i).to be >= 0
    end

    session = rsm.safe_get(session_id)
    expect(session['time_delta']).to be >= 0

    drop_counter = ->(env) {
      env['rack.session'].delete('counter')
      env['rack.session']['foo'] = 'bar'
      [200, {'Content-Type' => 'text/plain'}, env['rack.session'].inspect]
    }
    tses = Rack::Utils::Context.new(rsm, drop_counter)
    treq = Rack::MockRequest.new(tses)
    tnum = rand(7).to_i + 5
    r = Array.new(tnum) do |i|
      Thread.new(treq) do |run|
        run.get('/', 'HTTP_COOKIE' => cookie, 'rack.multithread' => true)
      end.run.join.value
    end.reverse
    r.each do |res|
      expect(res.body).to include '"foo"=>"bar"'
    end

    session = rsm.safe_get(session_id)
    expect(session['counter']).to be nil
    expect(session['foo']).to eq 'bar'
  end

end
