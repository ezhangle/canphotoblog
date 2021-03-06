fs = require 'fs'
path = require 'path'
util = require 'util'
step = require 'step'
im = require '../libs/img'
cutil = require '../libs/util'

app = module.parent.exports.expressApp
db = app.set 'db'
settings = app.set 'settings'

Pictures = require '../models/pictures'
pictures = new Pictures db, settings.albumDir


# GET /pictures/album/picture.ext
app.get '/pictures/:album/:picture.:ext', (req, res) ->

  album = req.params.album
  picture = req.params.picture + '.' + req.params.ext

  step(

    # get picture
    () ->
      pictures.getPicture album, picture, @
      return undefined

    # render page
    (err, picinfo) ->
      if err then throw err
      if not picinfo then throw new Error('Picture not found: ' + album + '/' + picture)

      res.render 'picture', {
          locals: {
            pagetitle: picinfo.name
            picture: picinfo
          }
        }

  )


# GET /random
app.get '/random', (req, res) ->

  step(

    # get picture
    () ->
      pictures.getRandomPicture @
      return undefined

    # render page
    (err, pic) ->
      if err then throw err
      if not pic then throw new Error('Random picture not found.')
      res.redirect '/pictures/' + pic.album + '/' + pic.name

  )


# GET /thumbs/album/picture.ext
# Create the thumbnail on first request. Subsequent
# requests should be served by static provider with
# the thumbnail generated here.
app.get '/thumbs/:album/:picture.:ext', (req, res) ->

  album = req.params.album
  picture = req.params.picture
  ext = req.params.ext
  source = path.join settings.albumDir, album, picture + '.jpg'
  dest = path.join settings.thumbDir, album, picture + '.png'

  step(

    # check database
    () ->
      pictures.findPicture album, picture, @
      return undefined

    # check source
    (err, pic) ->
      if err then throw err
      if not pic then throw new Error('Picture not found:' + album + '/' + picture + '.' + ext)

      source = path.join settings.albumDir, pic.album, pic.name
      cutil.fileExists source, @
      return undefined

    # get thumbnail
    (err, exists) ->
      if err then throw err
      if not exists then throw new Error('Picture not found:' + album + '/' + picture + '.' + ext)

      im.makeThumbnail source, dest, settings.thumbSize, @
      return undefined

    # check if image exists
    (err) ->
      if err then throw err
      cutil.fileExists dest, @
      return undefined

    # read image
    (err, exists) ->
      if err then throw err
      if not exists then return null
      fs.readFile dest, @
      return undefined

    # output image
    (err, data) ->
      if err then throw err
      if data
        headers = {
          'Content-Type': 'image/jpeg'
          'Content-Length': data.length
        }
        res.writeHead 200, headers
        res.write data, 'binary'
        res.end()
      else
        res.render '404'
 
  )


# GET /pictures/rename
app.get '/pictures/rename/:album/:picture.:ext', (req, res) ->

  if req.session.userid

    album = req.params.album
    picture = req.params.picture + '.' + req.params.ext
    thumb = '/thumbs/' + req.params.album + '/' + req.params.picture + '.png'

    res.render 'renamepicture', {
        locals: {
          pagetitle: 'Rename Picture'
          albumname: album
          picturename: picture
          thumb: thumb
        }
      }

  else
    req.flash 'error', 'Access denied.'
    res.redirect '/login'


# POST /pictures/rename
app.post '/pictures/rename', (req, res) ->

  if req.session.userid

    album = req.body.album
    picture = req.body.picture
    target = req.body.target

    target = path.basename(target, path.extname(target)) + '.jpg'

    pictures.rename album, picture, target, (err) ->
      if err then throw err
      res.redirect '/pictures/' + album + '/' + target

  else
    req.flash 'error', 'Access denied.'
    res.redirect '/login'


# GET /pictures/move
app.get '/pictures/move/:album/:picture.:ext', (req, res) ->

  if req.session.userid

    album = req.params.album
    picture = req.params.picture + '.' + req.params.ext
    thumb = '/thumbs/' + req.params.album + '/' + req.params.picture + '.png'

    res.render 'movepicture', {
        locals: {
          pagetitle: 'Move Picture'
          albumname: album
          picturename: picture
          thumb: thumb
        }
      }

  else
    req.flash 'error', 'Access denied.'
    res.redirect '/login'


# POST /pictures/move
app.post '/pictures/move', (req, res) ->

  if req.session.userid

    album = req.body.album
    picture = req.body.picture
    target = req.body.target

    pictures.move album, picture, target, (err) ->
      if err then throw err
      res.redirect '/albums/' + album

  else
    req.flash 'error', 'Access denied.'
    res.redirect '/login'


# POST /pictures/edit
app.post '/pictures/edit', (req, res) ->

  if req.session.userid

    album = req.body.album
    picture = req.body.picture
    title = req.body.title
    text = req.body.text

    if req.body.rename?
      res.redirect '/pictures/rename/' + album + '/' + picture
      return
    if req.body.move?
      res.redirect '/pictures/move/' + album + '/' + picture
      return
    if req.body.delete?
      pictures.delete album, picture, (err) ->
        if err then throw err
        res.redirect '/albums/' + album
      return
    if req.body.rotateleft?
      pictures.rotate album, picture, -90, (err) ->
        if err then throw err

        # delete old thumbnail
        pic = path.basename picture, path.extname(picture)
        thumb  = path.join settings.thumbDir, album, pic + '.png'
        fs.unlinkSync thumb

        res.redirect '/albums/' + album
      return
    if req.body.rotateright?
      pictures.rotate album, picture, 90, (err) ->
        if err then throw err


        # delete old thumbnail
        pic = path.basename picture, path.extname(picture)
        thumb  = path.join settings.thumbDir, album, pic + '.png'
        fs.unlinkSync thumb

        res.redirect '/albums/' + album
      return


    step(

      # edit picture
      () ->
        pictures.editPicture album, picture, title, text, @
        return undefined

      # go back
      (err, item) ->
        if err then throw err
        res.redirect '/pictures/' + album + '/' + picture

    )

  else
    req.flash 'error', 'Access denied.'
    res.redirect '/login'

