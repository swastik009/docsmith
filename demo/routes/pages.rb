# frozen_string_literal: true

module Demo
  # Demonstrates how Docsmith renders stored HTML under each html_sanitizer mode.
  #
  # Stored HTML is untrusted input: before 0.2.0 render(:html) returned it
  # verbatim, which is stored XSS whenever the content came from a user.
  class Pages < Sinatra::Base
    set :views, File.expand_path("../../views", __FILE__)

    # See routes/articles.rb — Sinatra's stock ERB does not escape <%= %>.
    set :erb, escape_html: true

    # The three modes, rendered side by side. Config is global, so each mode is
    # applied around a single render call and then restored.
    MODES = {
      "nil (default)" => nil,
      "callable"      => :configured,
      ":unsafe_raw"   => :unsafe_raw
    }.freeze

    get "/pages" do
      @pages = Page.order(created_at: :desc)
      erb :pages_index
    end

    post "/pages" do
      page = Page.create!(title: params[:title], body: params[:body])
      page.save_version!(author: User.first, summary: "Initial draft")
      redirect "/pages/#{page.id}"
    end

    get "/pages/:id" do
      @page    = Page.find(params[:id])
      @version = @page.current_version
      @renders = render_under_each_mode(@version)
      erb :page
    end

    post "/pages/:id/versions" do
      page = Page.find(params[:id])
      page.update_column(:body, params[:body])
      page.send(:_docsmith_document).update_column(:content, params[:body])
      page.save_version!(author: User.first, summary: params[:summary].presence || nil)
      redirect "/pages/#{page.id}"
    end

    private

    # @param version [Docsmith::DocumentVersion, nil]
    # @return [Hash{String => String}] mode label => rendered output (or the raised error)
    def render_under_each_mode(version)
      return {} if version.nil?

      original = Docsmith.configuration.html_sanitizer

      MODES.transform_values do |mode|
        Docsmith.configuration.html_sanitizer = mode == :configured ? original : mode
        begin
          version.render(:html)
        rescue Docsmith::InvalidHtmlSanitizer => e
          "#{e.class}: #{e.message}"
        end
      end
    ensure
      Docsmith.configuration.html_sanitizer = original
    end
  end
end
