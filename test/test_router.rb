require 'helper'

module Journey
  class TestRouter < MiniTest::Unit::TestCase
    def setup
      @router = Router.new({})
    end

    def test_request_class_reader
      klass = Object.new
      router = Router.new(:request_class => klass)
      assert_equal klass, router.request_class
    end

    class FakeRequestFeeler < Struct.new(:env, :called)
      def new env
        self.env = env
        self
      end

      def hello
        self.called = true
        'world'
      end
    end

    def test_request_class_and_requirements_success
      klass  = FakeRequestFeeler.new nil
      router = Router.new({:request_class => klass })

      requirements = { :hello => /world/ }

      exp = Router::Strexp.new '/foo(/:id)', {}, ['/.?']
      path  = Path::Pattern.new exp

      router.add_route nil, {:path_info => path}.merge(requirements), {:id => nil}, {}

      env = rails_env 'PATH_INFO' => '/foo/10'
      router.recognize(env) do |r, _, params|
        assert_equal({:id => '10'}, params)
      end

      assert klass.called, 'hello should have been called'
      assert_equal env.env, klass.env
    end

    def test_request_class_and_requirements_fail
      klass  = FakeRequestFeeler.new nil
      router = Router.new({:request_class => klass })

      requirements = { :hello => /mom/ }

      exp = Router::Strexp.new '/foo(/:id)', {}, ['/.?']
      path  = Path::Pattern.new exp

      router.add_route nil, {:path_info => path}.merge(requirements), {:id => nil}, {}

      env = rails_env 'PATH_INFO' => '/foo/10'
      router.recognize(env) do |r, _, params|
        flunk 'route should not be found'
      end

      assert klass.called, 'hello should have been called'
      assert_equal env.env, klass.env
    end

    def test_required_parts_verified_are_anchored
      add_routes @router, [
        Router::Strexp.new("/foo/:id", { :id => /\d/ }, ['/', '.', '?'], false)
      ]

      assert_raises(Router::RoutingError) do
        @router.generate(:path_info, nil, { :id => '10' }, { })
      end
    end

    def test_required_parts_are_verified_when_building
      add_routes @router, [
        Router::Strexp.new("/foo/:id", { :id => /\d+/ }, ['/', '.', '?'], false)
      ]

      path, _ = @router.generate(:path_info, nil, { :id => '10' }, { })
      assert_equal '/foo/10', path

      assert_raises(Router::RoutingError) do
        @router.generate(:path_info, nil, { :id => 'aa' }, { })
      end
    end

    def test_only_required_parts_are_verified
      add_routes @router, [
        Router::Strexp.new("/foo(/:id)", {:id => /\d/}, ['/', '.', '?'], false)
      ]

      path, _ = @router.generate(:path_info, nil, { :id => '10' }, { })
      assert_equal '/foo/10', path

      path, _ = @router.generate(:path_info, nil, { }, { })
      assert_equal '/foo', path

      path, _ = @router.generate(:path_info, nil, { :id => 'aa' }, { })
      assert_equal '/foo/aa', path
    end

    def test_X_Cascade
      add_routes @router, [ "/messages(.:format)" ]
      resp = @router.call({ 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/lol' })
      assert_equal ['Not Found'], resp.last
      assert_equal 'pass', resp[1]['X-Cascade']
      assert_equal 404, resp.first
    end

    def test_defaults_merge_correctly
      path  = Path::Pattern.new '/foo(/:id)'
      @router.add_route nil, {:path_info => path}, {:id => nil}, {}

      env = rails_env 'PATH_INFO' => '/foo/10'
      @router.recognize(env) do |r, _, params|
        assert_equal({:id => '10'}, params)
      end

      env = rails_env 'PATH_INFO' => '/foo'
      @router.recognize(env) do |r, _, params|
        assert_equal({:id => nil}, params)
      end
    end

    def test_recognize_with_unbound_regexp
      add_routes @router, [
        Router::Strexp.new("/foo", { }, ['/', '.', '?'], false)
      ]

      env = rails_env 'PATH_INFO' => '/foo/bar'

      @router.recognize(env) { |*_| }

      assert_equal '/foo', env.env['SCRIPT_NAME']
      assert_equal '/bar', env.env['PATH_INFO']
    end

    def test_bound_regexp_keeps_path_info
      add_routes @router, [
        Router::Strexp.new("/foo", { }, ['/', '.', '?'], true)
      ]

      env = rails_env 'PATH_INFO' => '/foo'

      before = env.env['SCRIPT_NAME']

      @router.recognize(env) { |*_| }

      assert_equal before, env.env['SCRIPT_NAME']
      assert_equal '/foo', env.env['PATH_INFO']
    end

    def test_path_not_found
      add_routes @router, [
        "/messages(.:format)",
        "/messages/new(.:format)",
        "/messages/:id/edit(.:format)",
        "/messages/:id(.:format)"
      ]
      env = rails_env 'PATH_INFO' => '/messages/1.1.1'
      yielded = false

      @router.recognize(env) do |*whatever|
        yielded = false
      end
      refute yielded
    end

    def test_required_part_in_recall
      add_routes @router, [ "/messages/:a/:b" ]

      path, _ = @router.generate(:path_info, nil, { :a => 'a' }, { :b => 'b' })
      assert_equal "/messages/a/b", path
    end

    def test_splat_in_recall
      add_routes @router, [ "/*path" ]

      path, _ = @router.generate(:path_info, nil, { }, { :path => 'b' })
      assert_equal "/b", path
    end

    def test_recall_should_be_used_when_scoring
      add_routes @router, [
        "/messages/:action(/:id(.:format))",
        "/messages/:id(.:format)"
      ]

      path, _ = @router.generate(:path_info, nil, { :id => 10 }, { :action => 'index' })
      assert_equal "/messages/index/10", path
    end

    def add_routes router, paths
      paths.each do |path|
        path  = Path::Pattern.new path
        router.add_route nil, {:path_info => path}, {}, {}
      end
    end

    def test_nil_path_parts_are_ignored
      path  = Path::Pattern.new "/:controller(/:action(.:format))"
      @router.add_route nil, {:path_info => path}, {}, {}

      params = { :controller => "tasks", :format => nil }
      extras = { :action => 'lol' }

      path, _ = @router.generate(:path_info, nil, params, extras)
      assert_equal '/tasks', path
    end

    def test_generate_slash
      path  = Path::Pattern.new '/'
      @router.add_route nil, {:path_info => path}, {}, {}

      params = [ [:controller, "tasks"],
                 [:action, "show"] ]

      path, _ = @router.generate(:path_info, nil, Hash[params], {})
      assert_equal '/', path
    end

    def test_generate_calls_param_proc
      path  = Path::Pattern.new '/:controller(/:action)'
      @router.add_route nil, {:path_info => path}, {}, {}

      parameterized = []
      params = [ [:controller, "tasks"],
                 [:action, "show"] ]

      @router.generate(
        :path_info,
        nil,
        Hash[params],
        {},
        { :parameterize => lambda { |k,v| parameterized << [k,v]; v } })

      assert_equal params.sort, parameterized.sort
    end

    def test_generate_id
      path  = Path::Pattern.new '/:controller(/:action)'
      @router.add_route nil, {:path_info => path}, {}, {}

      path, params = @router.generate(
        :path_info, nil, {:id=>1, :controller=>"tasks", :action=>"show"}, {})
      assert_equal '/tasks/show', path
      assert_equal({:id => 1}, params)
    end

    # FIXME I *guess* this isn't required??
    def test_generate_escapes
      path  = Path::Pattern.new '/:controller(/:action)'
      @router.add_route nil, {:path_info => path}, {}, {}

      path, _ = @router.generate(:path_info,
        nil, { :controller        => "tasks",
               :action            => "show me",
      }, {})
      assert_equal '/tasks/show me', path
    end

    def test_generate_extra_params
      path  = Path::Pattern.new '/:controller(/:action)'
      @router.add_route nil, {:path_info => path}, {}, {}

      path, params = @router.generate(:path_info,
        nil, { :id                => 1,
               :controller        => "tasks",
               :action            => "show",
               :relative_url_root => nil
      }, {})
      assert_equal '/tasks/show', path
      assert_equal({:id => 1, :relative_url_root => nil}, params)
    end

    def test_generate_uses_recall_if_needed
      path  = Path::Pattern.new '/:controller(/:action(/:id))'
      @router.add_route nil, {:path_info => path}, {}, {}

      path, params = @router.generate(:path_info,
        nil,
        {:controller =>"tasks", :id => 10},
        {:action     =>"index"})
      assert_equal '/tasks/index/10', path
      assert_equal({}, params)
    end

    def test_generate_with_name
      path  = Path::Pattern.new '/:controller(/:action)'
      @router.add_route nil, {:path_info => path}, {}, {}

      path, params = @router.generate(:path_info,
        "tasks",
        {:controller=>"tasks"},
        {:controller=>"tasks", :action=>"index"})
      assert_equal '/tasks', path
      assert_equal({}, params)
    end

    {
      '/content'            => { :controller => 'content' },
      '/content/list'       => { :controller => 'content', :action => 'list' },
      '/content/show/10'    => { :controller => 'content', :action => 'show', :id => "10" },
    }.each do |request_path, expected|
      define_method("test_recognize_#{expected.keys.map(&:to_s).join('_')}") do
        path  = Path::Pattern.new "/:controller(/:action(/:id))"
        app   = Object.new
        route = @router.add_route(app, { :path_info => path }, {}, {})

        env = rails_env 'PATH_INFO' => request_path
        called   = false

        @router.recognize(env) do |r, _, params|
          assert_equal route, r
          assert_equal(expected, params)
          called = true
        end

        assert called
      end
    end

    def test_namespaced_controller
      strexp = Router::Strexp.new(
        "/:controller(/:action(/:id))",
        { :controller => /.+?/ },
        ["/", ".", "?"]
      )
      path  = Path::Pattern.new strexp
      app   = Object.new
      route = @router.add_route(app, { :path_info => path }, {}, {})

      env = rails_env 'PATH_INFO' => '/admin/users/show/10'
      called   = false
      expected = {
        :controller => 'admin/users',
        :action     => 'show',
        :id         => '10'
      }

      @router.recognize(env) do |r, _, params|
        assert_equal route, r
        assert_equal(expected, params)
        called = true
      end
      assert called
    end

    def test_recognize_literal
      path   = Path::Pattern.new "/books(/:action(.:format))"
      app    = Object.new
      route  = @router.add_route(app, { :path_info => path }, {:controller => 'books'})

      env    = rails_env 'PATH_INFO' => '/books/list.rss'
      expected = { :controller => 'books', :action => 'list', :format => 'rss' }
      called = false
      @router.recognize(env) do |r, _, params|
        assert_equal route, r
        assert_equal(expected, params)
        called = true
      end

      assert called
    end

    def test_recognize_cares_about_verbs
      path   = Path::Pattern.new "/books(/:action(.:format))"
      app    = Object.new
      conditions = {
        :path_info      => path,
        :request_method => 'GET'
      }
      @router.add_route(app, conditions, {})

      conditions = conditions.dup
      conditions[:request_method] = 'POST'

      post = @router.add_route(app, conditions, {})

      env = rails_env 'PATH_INFO' => '/books/list.rss',
                      "REQUEST_METHOD"    => "POST"

      called = false
      @router.recognize(env) do |r, _, params|
        assert_equal post, r
        called = true
      end

      assert called
    end

    private

    RailsEnv = Struct.new(:env)

    def rails_env env
      RailsEnv.new rack_env env
    end

    def rack_env env
      {
        "rack.version"      => [1, 1],
        "rack.input"        => StringIO.new,
        "rack.errors"       => StringIO.new,
        "rack.multithread"  => true,
        "rack.multiprocess" => true,
        "rack.run_once"     => false,
        "REQUEST_METHOD"    => "GET",
        "SERVER_NAME"       => "example.org",
        "SERVER_PORT"       => "80",
        "QUERY_STRING"      => "",
        "PATH_INFO"         => "/content",
        "rack.url_scheme"   => "http",
        "HTTPS"             => "off",
        "SCRIPT_NAME"       => "",
        "CONTENT_LENGTH"    => "0"
      }.merge env
    end
  end
end
