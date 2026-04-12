# frozen_string_literal: true

module Demo
  class Articles < Sinatra::Base
    set :views, File.expand_path("../../views", __FILE__)

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
