# cms.rb 

require 'sinatra'
require 'sinatra/reloader' if development?
require 'redcarpet'
require 'yaml'
require 'bcrypt'
require 'fileutils'

configure do
  enable :sessions
  set :session_secret, 'super secret'
  set :erb, :escape_html => true
end

before do
  @markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
end


# Global Scope methods for testing
def users
  YAML.load_file(yml_path)
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def yml_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/user_accounts.yml", __FILE__)
  else
    File.expand_path("../user_accounts.yml", __FILE__)
  end
end

def get_path(filename)
  File.join(data_path, filename)
end

def valid_password?(username, password)
  hsh = users[username]
  hsh && BCrypt::Password.new(hsh) == password
end

helpers do
  def get_files
    pattern = get_path('*')
    Dir.glob(pattern).map{ |path| File.basename(path) }
  end

  def file_exists?(filename)
    filenames = get_files
    filenames.include?(filename)
  end

  def valid_filename?(filename)
    return false if filename.empty?
    pattern = get_path('*')
    Dir.glob(pattern).all?{ |path| File.basename(path) != filename }
  end

  def insert_index(filename, idx)
    basename = File.basename(filename, '.*')
    if basename.split('_').last.to_i != 0
      basename = basename.split('_')[0..-2].join('_')
    end
    extension = File.extname(filename)
    if extension != ''
      return "#{basename}_#{idx}#{extension}"
    else
      return "#{basename}_#{idx}"
    end
  end

  def new_name(filename)
    output = ''
    i = 1
    until valid_filename?(output) do
      output = insert_index(filename, i)
      i += 1
    end
    output
  end

  def load_file(filename)
    content = File.read(get_path(filename))
    case File.extname(filename)
    when '.md'
      erb @markdown.render(content), layout: :layout
    when '.txt'
      headers['Content-Type'] = 'text/plain'
      content
    end  
  end

  def users_only
    unless session[:signed_in]
      session[:message] = 'You must be signed in to do that.'
      redirect '/users/signin'
    end
  end

  def valid_new_user?(username)
    usernames = users.keys.map(&:downcase)
    username != '' && !usernames.include?(username.downcase)
  end

  def valid_new_password?(password)
    password.length >= 6
  end
end

# index - homepage
get '/' do
  users_only

  @files = get_files
  erb :home, layout: :layout
end

# new document page
get '/new' do
  users_only
  erb :new, layout: :layout
end

# create new document
post '/' do
  users_only

  new_file = params[:new_file]
  if valid_filename?(new_file)
    session[:message] = "#{new_file} has been created."
    path = get_path(new_file)
    File.open(path, 'w')
    redirect '/'
  else
    session[:message] = "Filename must be nonempty and unique."
    redirect '/new'
  end
end

# access particular file
get '/:filename' do
  filename = File.basename(params[:filename])
  @files = get_files

  if file_exists?(filename)
    load_file(filename)
  else
    session[:message] = "#{filename} does not exist."
    redirect '/'
  end
end

# duplicate a file
post '/:filename/duplicate' do
  users_only
  filename = params[:filename]
  src = get_path(filename)
  dest = get_path(new_name(filename))

  FileUtils.cp(src, dest)
  session[:message] = "A duplicate of #{filename} has been created at #{dest}"
  redirect '/'
end

# edit content of particular file
get '/:filename/edit' do
  users_only

  @filename = params[:filename]
  path = get_path(@filename)

  @old_content = File.read(path)

  erb :edit, layout: :layout
end

# update content of file to match edit submission
post '/:filename' do
  users_only

  filename = params[:filename]
  session[:message] = "#{filename} has been edited."
  path = get_path(filename)

  new_content = params[:new_content]
  File.open(path, 'w'){ |file| file.puts new_content }
  redirect '/'
end

# delete a file
post '/:filename/delete' do
  users_only

  filename = params[:filename]
  session[:message] = "#{filename} was deleted."
  path = get_path(filename)
  File.delete(path)
  redirect '/'
end

# sign in
get '/users/signin' do
  erb :signin, layout: :layout
end

# validate credentials
post '/users/signin' do
  username = params[:username]
  password = params[:password]
  hsh = users[username]
  if valid_password?(username, password) || session[:signed_in]
    session[:signed_in] = username
    session[:message] = 'Welcome!'
    redirect '/'
  else
    session[:message] = 'Invalid Credentials'
    status 422
    erb :signin, layout: :layout
  end
end

# signout
post '/users/signout' do
  session.delete(:signed_in)
  session[:message] = 'You were signed out.'
  redirect '/users/signin'
end

# create new account form
get '/users/signup' do
  erb :signup, layout: :layout
end

# create new account
post '/users/signup' do
  username = params[:username]
  password = params[:password]
  if valid_new_user?(username) && valid_new_password?(password)
    session[:message] = "New account created for #{username}. Welcome!"
    hsh = BCrypt::Password.create(password)
    File.open("#{yml_path}", 'a+'){ |f| f.write("\n#{username}: '#{hsh}'") }
    session[:signed_in] = username
    redirect '/'
  elsif valid_new_user?(username)
    session[:message] = "Passwords must be at least 6 characters."
    status 422
    erb :signup, layout: :layout
  else
    session[:message] = "Invalid Username. Username must be at least one character and unique."
    status 422
    erb :signup, layout: :layout
  end
end
