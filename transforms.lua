-- Crop the first party-ball tile from the player's imported sheet. The mod
-- ships only this recipe; no ROM-derived image data is included.
return function(ctx)
  if not ctx.exists("battle/balls.png") then return end
  local source = ctx.readImage("battle/balls.png")
  local ball = ctx.blank(8, 8)
  ctx.blit(ball, source, 0, 0, 0, 0, 8, 8)
  ctx.writeImage(ball, "ui/ball.png")
end
