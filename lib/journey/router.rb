require 'journey/router/utils'
require 'journey/router/strexp'

before = $-w
$-w = false
require 'journey/definition/parser'
$-w = before

require 'journey/route'
require 'journey/path/pattern'

require 'journey/backwards' # backwards compat stuff

module Journey
  class Router
    class RoutingError < ::StandardError
    end

    VERSION = '1.0.0'

    attr_reader :routes, :named_routes

    def initialize options
      @options      = options
      @routes       = []
      @named_routes = {}
    end

    def add_route app, conditions, defaults, name = nil
      path = conditions[:path_info]
      route = Route.new(app, path, nil, defaults)
      routes << route
      named_routes[name] = route if name
      route
    end

    def generate part, name, options, recall = nil, parameterize = nil
      route = named_routes[name] || routes.sort_by { |r| r.score(options) }.last

      route.format(options.to_a - route.extras.to_a)
    end

    def call env
      [200, {}, []]
    end

    def recognize req
      match_data = nil
      route = routes.find do |route|
        match_data = route.path =~ req.env['PATH_INFO']
      end

      yield(route, nil, match_data.merge(route.extras))
    end
  end
end
