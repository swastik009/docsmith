# frozen_string_literal: true

module Demo
  class Articles < Sinatra::Base
    set :views, File.expand_path("../../views", __FILE__)

    # Sinatra's stock ERB does NOT escape <%= %>. Without this, an article title
    # or comment body containing a <script> tag executes in the browser.
    # Use <%== %> for the few places that intentionally emit HTML.
    set :erb, escape_html: true

    get "/" do
      @articles = Article.order(created_at: :desc)
      erb :index
    end

    post "/articles" do
      @article = Article.create!(title: params[:title], body: params[:body])
      author = User.first
      @article.save_version!(author: author, summary: "Initial draft")
      redirect "/articles/#{@article.id}"
    end

    get "/articles/:id" do
      @article = Article.find(params[:id])
      @versions = @article.versions.order(version_number: :asc)
      @current  = @article.current_version
      erb :article
    end

    post "/articles/:id/versions" do
      article = Article.find(params[:id])
      article.update_column(:body, params[:body])
      article.send(:_docsmith_document).update_column(:content, params[:body])
      author = User.first
      v = article.save_version!(author: author, summary: params[:summary].presence || nil)
      redirect "/articles/#{article.id}" + (v.nil? ? "?notice=unchanged" : "")
    end

    post "/articles/:id/restore" do
      article = Article.find(params[:id])
      article.restore_version!(params[:version_number].to_i, author: User.first)
      redirect "/articles/#{article.id}?notice=restored"
    end

    post "/articles/:id/tag" do
      article = Article.find(params[:id])
      begin
        article.tag_version!(params[:version_number].to_i,
                              name:   params[:tag_name],
                              author: User.first)
        redirect "/articles/#{article.id}?notice=tagged"
      rescue Docsmith::TagAlreadyExists
        redirect "/articles/#{article.id}?error=tag_exists"
      end
    end

    # The JSON export envelope for a single version.
    # Add ?parsed=1 on a json document to also get the "data" key.
    get "/articles/:id/versions/:n/export.json" do
      content_type :json
      article = Article.find(params[:id])
      version = article.version(params[:n].to_i)
      JSON.pretty_generate(version.export(include_parsed: params[:parsed] == "1"))
    end

    # A deliberately NESTED payload. This is the shape third-party clients actually
    # consume, and the one that used to differ from `result.to_json`: before
    # Diff::Result#as_json existed, the "diff" key below came out with no "stats"
    # and with "line" instead of "position".
    get "/articles/:id/diff.json" do
      content_type :json
      article = Article.find(params[:id])
      diff    = article.diff_between(params[:from].to_i, params[:to].to_i)

      JSON.pretty_generate(
        article:  { id: article.id, title: article.title },
        versions: article.versions.map { |v| v.export.slice("version_number", "content_type") },
        diff:     diff
      )
    end

    get "/articles/:id/diff" do
      @article = Article.find(params[:id])
      from = params[:from].to_i
      to   = params[:to].to_i
      @diff = @article.diff_between(from, to)
      @from = from
      @to   = to
      erb :diff
    end

    post "/articles/:id/comments" do
      article = Article.find(params[:id])
      version = article.version(params[:version_number].to_i)
      article.add_comment!(
        version: version.version_number,
        body:    params[:body],
        author:  User.first
      )
      redirect "/articles/#{article.id}"
    end

    post "/articles/:id/comments/:comment_id/resolve" do
      article = Article.find(params[:id])
      comment = Docsmith::Comments::Comment.find(params[:comment_id])
      Docsmith::Comments::Manager.resolve!(comment, by: User.first)
      redirect "/articles/#{article.id}"
    end
  end
end
