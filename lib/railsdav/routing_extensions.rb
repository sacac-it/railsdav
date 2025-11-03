# Extend routing s.t. webdav_resource and webdav_resources can be used,
# enabling things like PROPFIND /foo/index.(:format) and such.
#
# ATTENTION: adapt this to newer rails version if upgrading the framework!
class ActionDispatch::Routing::Mapper
  module HttpHelpers

    %w(propfind options copy move mkcol lock unlock proppatch).each do |method_name|
      define_method "dav_#{method_name}" do |*args, &block|
        options = args.extract_options!
        options[:via] = method_name
        match(*args, options, &block)
        self
      end
    end
  end

  module Resources
    CANONICAL_ACTIONS << 'update_all'

    class WebDAVResource < Resource
      DEFAULT_ACTIONS = [:index, :create, :new, :show, :update, :destroy, :edit, :update_all]

      def default_actions
        DEFAULT_ACTIONS
      end
    end

    class WebDAVSingletonResource < SingletonResource
      DEFAULT_ACTIONS = [:show, :create, :update, :destroy, :new, :edit]

      def default_actions
        DEFAULT_ACTIONS
      end
    end

    def resource_scope?
      [:webdav_resource, :webdav_resources, :resource, :resources].include?(@scope[:scope_level] || @scope.scope_level)
    end

    def dav_options_response(*allowed_http_verbs)
      proc { [200, {'Allow' => allowed_http_verbs.flatten.map{|s| s.to_s.upcase}.join(' '), 'DAV' => '1'}, [' ']] }
    end

    def dav_match(*args)
      get *args
      if args.last.is_a? Hash
        # prevents `Invalid route name, already in use`
        args.last.delete(:as)
        args.last.delete('as')
      end
      dav_propfind *args
    end

    def webdav_resource(*resources, &block)
      options = resources.extract_options!.dup

      if apply_common_behavior_for(:webdav_resource, resources, options, &block)
        return self
      end

      sub_block = proc do
        yield if block_given?

        if parent_resource.actions.include?(:create)
          collection do
            post :create
          end
        end

        if parent_resource.actions.include?(:new)
          new do
            get :new
          end
        end

        member do
          if parent_resource.actions.include?(:show)
            dav_match :show
          end
          get    :edit    if parent_resource.actions.include?(:edit)
          put    :update  if parent_resource.actions.include?(:update)
          delete :destroy if parent_resource.actions.include?(:destroy)
        end
      end

      with_scope_level :webdav_resource do
        resource_scope WebDAVResource.new(resources.pop, api_only?, options), &sub_block
      end

      self
    end

    def webdav_resources(*resources, &block)
      options = resources.extract_options!

      if apply_common_behavior_for(:webdav_resources, resources, **options, &block)
        return self
      end

      sub_block = proc do
        yield if block_given?

        opts = []
        collection do
          if parent_resource.actions.include?(:index)
            dav_match :index
            opts << [:get, :propfind]
          end

          if parent_resource.actions.include?(:create)
            post :create
            opts << :post
          end

          if parent_resource.actions.include?(:update_all)
            put :index, :action => :update_all
            opts << :put
          end
          dav_options :index, :to => dav_options_response(opts)
        end

        if parent_resource.actions.include?(:new)
          new do
            dav_match :new
            put :new, :action => :create
            dav_options :new, :to => dav_options_response(:get, :put, :propfind, :options)
          end
        end

        member do
          opts = []
          if parent_resource.actions.include?(:show)
            dav_match :show
            opts << :get
            opts << :propfind
          end

          if parent_resource.actions.include?(:update)
            put :update
            opts << :put
          end

          if parent_resource.actions.include?(:destroy)
            delete :destroy
            opts << :delete
          end

          dav_options :show, :to => dav_options_response(opts)

          if parent_resource.actions.include?(:edit)
            dav_match :edit
            dav_options :edit, :to => dav_options_response(:get, :propfind)
          end
        end
      end

      with_scope_level :webdav_resources do
        resource_scope WebDAVResource.new(resources.pop, api_only?, options), &sub_block
      end

      self
    end

  end
end
