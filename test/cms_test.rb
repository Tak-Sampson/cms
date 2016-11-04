ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require "yaml"

require_relative "../cms.rb"

class AppTest < Minitest::Test
  include Rack::Test::Methods
  include Rack::Session

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    src = File.expand_path("../../user_accounts.yml", __FILE__ )
    dest = yml_path
    FileUtils.cp(src, dest)
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm(yml_path)
  end

  def session
    last_request.env['rack.session']
  end

  def create_document(name, content = "")
    File.open(get_path(name), 'w') do |file|
      file.write(content)
    end
  end

  def admin_session
    { "rack.session" => { signed_in: 'admin' } }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/", {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, 'about.md'
    assert_includes last_response.body, 'changes.txt'
  end

  def test_md_render
    create_document "about.md", '#1993 - Yukihiro Matsumoto dreams up Ruby.'

    get '/about.md', {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, '<h1>1993 - Yukihiro Matsumoto dreams up Ruby.</h1>'
  end

  def test_txt
    create_document 'changes.txt', 'Content of file.'

    get '/changes.txt', {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, 'Content of file.'
  end

  def test_no_file
    get '/not_a_file.txt', {}, admin_session
    assert_equal 302, last_response.status
    new_url = last_response['Location']
    
    assert_equal 'not_a_file.txt does not exist.', session[:message]
    get new_url
    refute session[:message]
  end

  def test_edit
    create_document 'changes.txt'

    get '/changes.txt/edit', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, '<input type="submit" value="Save Changes">'
  end

  def test_change
    create_document 'changes.txt', 'Original content'

    get '/changes.txt', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Original content'

    post '/changes.txt', { new_content: 'This is the updated content of changes.txt' }
    assert_equal 302, last_response.status
    new_url = last_response['Location']
    assert_equal 'changes.txt has been edited.', session[:message]

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'This is the updated content of changes.txt'   
  end

  def test_new
    get '/new', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<label for='new_file'>Add a New Document:</label>"
  end

  def test_invalid_filename
    create_document 'taken_name.txt'

    post '/', { new_file: '' }, admin_session
    assert_equal 302, last_response.status
    assert_equal 'Filename must be nonempty and unique.', session[:message]

    post '/', new_file: 'taken_name.txt'
    assert_equal 302, last_response.status
    assert_equal 'Filename must be nonempty and unique.', session[:message]  
  end

  def test_valid_filename
    post '/', { new_file: 'newfile.txt' }, admin_session
    assert_equal 302, last_response.status
    assert_equal "newfile.txt has been created.", session[:message]

    get '/'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'newfile.txt'
    refute session[:message]
  end

  def test_duplication
    create_document('changes.txt', 'Content to be duplicated.')
    get '/', {}, admin_session

    2.times{ post '/changes.txt/duplicate' }
    assert_equal 302, last_response.status
    assert_includes session[:message], 'A duplicate of changes.txt has been created'

    get '/changes_1.txt'
    assert_includes last_response.body, 'Content to be duplicated.'

    get '/changes_2.txt'
    assert_includes last_response.body, 'Content to be duplicated.'
  end

  def test_deletion
    create_document 'to_be_deleted.txt'

    get '/', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'to_be_deleted.txt'

    post '/to_be_deleted.txt/delete'
    assert_equal 302, last_response.status
    assert_equal 'to_be_deleted.txt was deleted.', session[:message]

    2.times{ get '/' } # page refresh to remove message from response body
    assert_equal 200, last_response.status
    refute_includes last_response.body, 'to_be_deleted.txt'
    refute session[:message]
  end

  def test_sign_in_form
    get '/users/signin'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<button type='submit'>Sign In</button>"
  end

  def test_sign_in
    post '/users/signin', { username: 'wrong', password: 'invalid' }
    assert_equal 422, last_response.status
    refute session[:signed_in]
    assert_includes last_response.body, 'Invalid Credentials'

    post '/users/signin', { username: 'admin' }, admin_session
    assert_equal 302, last_response.status
    assert_equal 'Welcome!', session[:message]
    assert_equal 'admin', session[:signed_in]
  end

  def test_sign_out
    post '/users/signin', { username: 'admin' }, admin_session
    assert_equal 'admin', session[:signed_in]
    
    post '/users/signout'
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'You were signed out'
    assert_includes last_response.body, "<button type='submit'>Sign In</button>"
  end

  def test_access_restriction
    get '/about.md/edit'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    post '/changes.txt'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    get '/new'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    post '/'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    post '/changes.txt/delete'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    post '/changes.txt/duplicate'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_signup_form
    get '/users/signup'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Create a Username:'
  end

  def test_signup
    post '/users/signup', {username: 'admin'}
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid Username. Username must be at least one character and unique.'
  
    post '/users/signup', {username: 'new_user', password: 'short'}
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Passwords must be at least 6 characters.'

    post '/users/signup', {username: 'new_user', password: 'new_password'}
    assert_equal 302, last_response.status
    assert_equal "New account created for new_user. Welcome!", session[:message]

    post '/users/signout'
    post '/users/signin', {username: 'new_user', password: 'new_password'}
    assert_equal 'Welcome!', session[:message]
    assert_equal 'new_user', session[:signed_in]
  end
end
