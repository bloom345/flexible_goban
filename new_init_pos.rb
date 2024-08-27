require 'date'
# 例外クラス定義
class BoardFullException < Exception
  def initialize(message="cannot play any more moves!")
    super(message)
  end
end
class DuplicateException < Exception
  def initialize(message="new move is duplicated and won't be placed on the board.")
    super(message)
  end
end
class OutOfBoardException < Exception
  def initialize(message="coordinate of the move is out of board!")
    super(message)
  end
end
class ForbiddenMoveException < Exception
  def initialize(message="Forbidden move")
    super(message)
  end
end
class KoException < Exception
  def initialize(pos, message="Ko and cannot play at #{pos}")
    super(message)
  end
end

# (x, y)に指定の石を打つ
# @param [Fixnum] i; 手数（実際の手数-1）
# @param [String] current_stone; 黒か白か。"B"→黒、"W"→白
# @param [Fixnum] x_coord; x座標。左上始点の列座標 1始まり。
# @param [Fixnum] y_coord; y座標。左上始点の行座標 1始まり。
# @raise [OutOfBoardException] 座標でボードの外側を指定したときに投げられる例外
# @raise [BoardFullException] 打つ場所がないときに投げられる例外
# @raise [DuplicateException] 既に石が置かれているところに打とうとしたときに投げられる例外
# @raise [ForbiddenMoveException] 着手禁止点に打とうとしたときに投げられる例外
# @raise [KoException] コウで打てないときに投げられる例外
def play(i, current_stone, x_coord, y_coord)
  @ko_potential = nil unless @ko_potential && @ko_potential[0]==i-1 
  raise OutOfBoardException if x_coord > BOARD_SIZE || y_coord > BOARD_SIZE
  raise BoardFullException if @amount_of_stones >= (MAX-MIN+1) ** 2
  new_pos = [x_coord, y_coord]
  raise DuplicateException if @positions.include?(new_pos)
  @board[x_coord-1][y_coord-1] = current_stone
  no_of_breathing_points = search(x_coord-1, y_coord-1)
  # show_board(@check) # search後には、どのようにsearchしたかがshow_boardの引数に@checkを渡すことで確認できる。
  case no_of_breathing_points
  when 0
    if capture(x_coord-1, y_coord-1, current_stone, estimate: true).size > 0
      # 石がとれるなら着手禁止ではないが、コウならKoException投げる
      raise KoException.new(new_pos) if @ko_potential && new_pos==@ko_potential[2]
      @positions << new_pos
      print "#{i+1}:#{current_stone}#{new_pos}, "
      @sgf_string += "#{current_stone}[#{@num_to_alphabet[x_coord-1]}#{@num_to_alphabet[y_coord-1]}];"
    else
      @board[x_coord-1][y_coord-1] = "." # ロールバック
      raise ForbiddenMoveException
    end
  else
    @positions << new_pos
    print "#{i+1}:#{current_stone}#{new_pos}, "
    @sgf_string += "#{current_stone}[#{@num_to_alphabet[x_coord-1]}#{@num_to_alphabet[y_coord-1]}];"
  end
  @amount_of_stones += 1
  capped_pos=capture(x_coord-1, y_coord-1, current_stone)
  if capped_pos.size==1 && no_of_breathing_points==0 && group_positions(x_coord-1, y_coord-1, false).size==1
    @ko_potential=[i, new_pos, capped_pos.first]
    puts "Ko potential #{@ko_potential}"
  end
  @amount_of_stones -= capped_pos.size
  show_board
end

# @param [String] stone; 
# @return stoneの反対の色を返す
def opposite(stone)
  stone == "B" ? "W" : "B"
end

# チェック用ボードの(x_pos, y_pos)にある石に属するグループを配列で返す
# @param [Fixnum] x_pos 列座標（0始まり）
# @param [Fixnum] y_pos 行座標（0始まり）
# @param [True/False] already_searched 同じ引数で直前にsearchメソッドが実行されている(=@checkが更新されている)かどうか
# @return [Array<Array>] 指定のx_pos, y_posの石が属するグループの座標を[[0, 2], [0, 3], [1, 3], ...] のような配列で返す。（0始まり）
def group_positions(x_pos, y_pos, already_searched=true)
  search(x_pos, y_pos) unless already_searched
  board = @check
  stone = board[x_pos][y_pos]
  coords = []
  board.each_with_index do |col, x|
    col.each_with_index do |row, y|
      coords << [x, y] if row==stone
    end
  end
  coords
end

# 今打った石によって、呼吸点が0になった石群を取り除く
# @param [Fixnum] x_pos 今打った石の列座標（0始まり）
# @param [Fixnum] y_pos 今打った石の行座標（0始まり）
# @param [String] stone 今打った石の色（"B"or"W"）
# @param [True/False] estimate @board, @positionsを実際に操作せずに石をとれるかどうか確認する
# @return [Array<Array>] アゲハマの座標の配列（1始まり）
def capture(x_pos, y_pos, stone, estimate: false)
  capped_stone_pos=[]
  # 隣接点についてそれぞれ確認
  [[x_pos+1,y_pos], [x_pos,y_pos+1], [x_pos-1,y_pos], [x_pos,y_pos-1]].each do |x, y|
    next unless x.between?(0,BOARD_SIZE-1) && y.between?(0,BOARD_SIZE-1) && @board[x][y]==opposite(stone)
    next unless search(x,y)==0
    group_positions(x,y).each do |capped_x, capped_y|
      unless estimate
        @board[capped_x][capped_y] = "."
        @positions.delete([capped_x+1, capped_y+1])
        puts "#{opposite(stone)}@(#{capped_x+1}, #{capped_y+1}) is captured."
      end
      capped_stone_pos << [capped_x+1, capped_y+1]
    end
  end
  capped_stone_pos
end

# 盤面の表示
def show_board(board=@board)
  print "\n"
  board.transpose.each do |column|
    column.each { |e| print e }; print "\n"
  end
end

# 有効着手点の座標を取得
def valid_moves(board=@board)
  valid_moves_hash = {"B"=>[], "W"=>[]}
  board.each_with_index do |col, x|
    col.each_with_index do |row, y|
      next unless board[x][y]=="." && x.between?(MIN-1, MAX-1) && y.between?(MIN-1, MAX-1) 
      valid_moves_hash.keys.each do |stone|
	board[x][y] = stone
	unless search(x,y)==0 && capture(x, y, stone, estimate: true).size==0
	  # 呼吸点が0で、石も一つも取れない場合には着手禁止点
	  valid_moves_hash[stone] << [x, y] 
        end
        board[x][y] = "."
      end
    end
  end
  valid_moves_hash
end

# 座標を与えて、その座標にある石が属するグループの呼吸点の数を数える。
# @param [Fixnum] x_pos; 0始まりのx座標
# @param [Fixnum] y_pos; 0始まりのy座標
# @param [String] stone; 黒なら"B"、白なら"W"
# @return [Fixnum] 呼吸点の数
def search(x_pos, y_pos, stone=nil)
  unless x_pos.between?(0,BOARD_SIZE-1) && y_pos.between?(0,BOARD_SIZE-1)
    0
  else
    pos = @board[x_pos][y_pos] 
    if stone == nil # 最初の呼び出し
      @check = Array.new(BOARD_SIZE) { Array.new(BOARD_SIZE, 0)} 
      if pos == "." || pos == nil # ナンセンスなのでnilを返す
        nil 
      else # posは"B"か"W"
	@check[x_pos][y_pos] = pos
	search(x_pos+1, y_pos, pos) + search(x_pos, y_pos+1, pos) + search(x_pos-1, y_pos, pos) + search(x_pos, y_pos-1, pos) 
      end
    else 
      if @check[x_pos][y_pos] != 0 # 探索済
	 0 
      else 
	case pos
	when "." # 空点 このときのみ呼吸点が増える
	  @check[x_pos][y_pos] = pos
	  1
	when stone
	  @check[x_pos][y_pos] = pos
	  search(x_pos+1, y_pos, pos) + search(x_pos, y_pos+1, pos) + search(x_pos-1, y_pos, pos) + search(x_pos, y_pos-1, pos) 
	else # 違う色の石
	  @check[x_pos][y_pos] = pos
	  0
	end    
      end
    end
  end
end
#-----------------------------------------------------------------------------------
# 環境変数取得
FUSEKI_STONES_AMOUNT = (ENV["STONES"] || 10).to_i
BOARD_SIZE = (ENV["SZ"] || 13).to_i # ボードサイズ 最大19
COORDS = ENV["COORDS"] # "B[aa];W[ab]; ..." という文字列
MIN = COORDS ? 1 : (ENV["MIN"] || 2).to_i # MIN線以上に配置 MIN=3なら3線より上にしか配置しない
MAX = BOARD_SIZE-MIN+1 
KOMI = (ENV["KM"] || 6.5).to_f
RULE = ENV["RU"] || "Japanese" # Japanese or Chinese
PB = ENV["PB"] || "black" # 黒番プレイヤー名
PW = ENV["PW"] || "white" # 白番プレイヤー名

# バリデーション
raise "Board size should be equal to or less than 19!" if BOARD_SIZE > 19
raise "Environment variable MIN should be less than half of board size!" if MIN > MAX

# インスタンス変数初期化
@board = Array.new(BOARD_SIZE) { Array.new(BOARD_SIZE, '.')} 
@num_to_alphabet = (:a..:z).to_a # 座標→アルファベットの変換用配列
@positions = [] # 重複判定用
@sgf_string = "(;GM[1]SZ[#{BOARD_SIZE}]PB[#{PB}]PW[#{PW}]KM[#{KOMI}]RU[#{RULE}];"
@amount_of_stones = 0

if COORDS
  moves = COORDS.split(";")
  moves.each_with_index do |pos_str, i|
    begin 
      current_stone = pos_str[0]
      x_coord = @num_to_alphabet.index(pos_str[2].to_sym)+1
      y_coord = @num_to_alphabet.index(pos_str[3].to_sym)+1
      vm_hash = valid_moves
      puts vm_hash.to_s
      # 黒も白も打てなければ例外、どちらか打てるならパス
      raise BoardFullException if vm_hash[current_stone].size==0 && vm_hash[opposite(current_stone)].size==0
      if vm_hash[current_stone].size==0
        puts "No valid moves. Pass"
        next
      end
      play(i, current_stone, x_coord, y_coord)
    rescue BoardFullException => e
      puts e.message
      break 
    rescue DuplicateException
      next # 座標指定の場合にはやり直しできないのでnext
    rescue ForbiddenMoveException
      next # 座標指定の場合にはやり直しできないのでnext
    rescue KoException => e
      puts e.message
      puts "Skipped."
      next
    end
  end
else
  (FUSEKI_STONES_AMOUNT*2).times do |i|
    begin
      current_stone = (i % 2 == 0) ? "B" : "W"
      vm_hash = valid_moves
      puts vm_hash.to_s
      # 黒も白も打てなければ例外、どちらか打てるならパス
      raise BoardFullException if vm_hash[current_stone].size==0 && vm_hash[opposite(current_stone)].size==0
      if vm_hash[current_stone].size==0
        puts "No valid moves. Pass"
        next
      end
      new_move = vm_hash[current_stone].sample
      play(i, current_stone, new_move[0]+1, new_move[1]+1)
    rescue BoardFullException => e
      puts e.message
      break 
    rescue DuplicateException
      redo
    rescue ForbiddenMoveException => e
      puts e.message
      redo # ランダム生成で着手禁止点に打たれた場合には繰り返し
    rescue KoException => e
      puts e.message
      puts "Retrying.."
      redo 
    end
  end
end

@sgf_string += ")"
puts @sgf_string
filename = COORDS ? "sgf/fixed_SZ#{BOARD_SIZE}_MV#{moves.size}_#{DateTime.now.strftime('%Y%m%d%H%M%S')}.sgf" : "sgf/random_SZ#{BOARD_SIZE}_NOS#{FUSEKI_STONES_AMOUNT}_#{DateTime.now.strftime('%Y%m%d%H%M%S')}.sgf" 
begin
  File.open(filename, "w") do |f|
    f.write(@sgf_string)
  end
  puts "Successfully output #{filename}"
rescue => e
  puts "Failed to output #{filename}"
  puts "ERROR: #{e.message}"
end
