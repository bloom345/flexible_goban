require 'set'
class Board
  attr_accessor :edges, :nodes, :check0
  # @param [Array] array 両端の点のIDを配列要素として持つような配列（＝辺を表現）の配列。
  # 例：玉碁の辺
  # [[1,2],[1,5],[1,8],[2,3],[2,10],[3,4],[3,12],[4,5],[4,14],[5,6],
  # [6,7],[6,15],[7,8],[7,17],[8,9],[9,10],[9,18],[10,11],[11,12],[11,19],
  # [12,13],[13,14],[13,20],[14,15],[15,16],[16,17],[16,20],[17,18],[18,19],[19,20],
  # [21,22],[21,25],[21,28],[22,23],[22,30],[23,24],[23,32],[24,25],[24,34],[25,26],
  # [26,27],[26,35],[27,28],[27,37],[28,29],[29,30],[29,38],[30,31],[31,32],[31,39],
  # [32,33],[33,34],[33,40],[34,35],[35,36],[36,37],[36,40],[37,38],[38,39],[39,40],
  # [1,21],[2,22],[3,23],[4,24],[5,25],[6,26],[7,27],[8,28],[9,29],[10,30],
  # [11,31],[12,32],[13,33],[14,34],[15,35],[16,36],[17,37],[18,38],[19,39],[20,40]]
  # 接続関係を定義する。辺が存在するところが1、しないところは0とする。隣接していても辺が存在しない場合があるのでその点に注意。
  # 通常、点から伸びる辺の数が4本までサポートすればよいが、一般にn本をサポートできるようにしたい。
  # 辺が繋いでいる点のIDを組として持つ辺の集まりを定義する方がわかりやすいか。例えば、[[0,1]] というのは点0と点1を結ぶ辺一つからなる碁盤をあらわす。
  # この場合、「座標」という概念はどうなるか？
  # 座標は必ずしも必要ではないかもしれない。ただ便利のために定義できてもよい。
  def initialize(array)
    @edges = Set.new
    array.each do |edge|
      @edges.add(Set.new(edge))
    end
    @nodes = {}
    @check0 = {}
    array.flatten.uniq.sort.each do |node_id| # 昇順にソート
      @nodes[node_id] = "." # 黒("B")か白("W")か、空点(".")かを保持。nilはボード外。
      @check0[node_id] = 0 # search用盤
    end
    @node_num = @nodes.size
  end

  # @param [Fixnum] node_id; ノードID
  # @return [Array] 指定したノードに接続している全ての辺
  def connected_edges(node_id)
    con_edges = []  
    @edges.each do |edge|
      con_edges << edge if edge.member?(node_id)
    end
    con_edges
  end

  # @param [Fixnum] node_id
  # @return [Array] 全ての隣接ノード
  def connected_nodes(node_id)
    con_nodes = []
    connected_edges(node_id).each do |edge|
      # edgeは2つの要素しか持たない→node_id以外のノードを取得
      con_nodes << edge.select{|e|e!=node_id}.first
    end
    con_nodes
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
  def play(i, current_stone, node_id)
    @ko_potential = nil unless @ko_potential && @ko_potential[0]==i-1 # 直前の手で作成された@ko_potentialであれば保持
    raise OutOfBoardException unless @nodes.include?(node_id)
    raise BoardFullException if @amount_of_stones >= @node_num # まずは石の数で判定
    new_pos = node_id
    raise DuplicateException if @positions.include?(new_pos)
    @nodes[new_pos] = current_stone
    # 有効性の事前チェック
    # TODO: 三劫や長生のチェックも将来的に必要
    no_of_breathing_points = search(node_id)
    # show_board(@check) # search後には、どのようにsearchしたかがshow_boardの引数に@checkを渡すことで確認できる。
    if no_of_breathing_points == 0 # 呼吸点がゼロの場合。通常は着手禁止点だが、石がとれるなら着手禁止ではない（ただし、コウを連打している場合にはKoExceptionを投げる）
      if capture(node_id, current_stone, estimate: true).size > 0 
        raise KoException.new(new_pos) if @ko_potential && new_pos==@ko_potential[2]
        # @sgf_string += "#{current_stone}[#{@num_to_alphabet[x_coord-1]}#{@num_to_alphabet[y_coord-1]}];"
      else
        @nodes[new_pos] = "." # ロールバック
        raise ForbiddenMoveException
      end
    end
    # 石を打つ
    @positions << new_pos
    @amount_of_stones += 1
    print "#{i+1}:#{current_stone}#{new_pos}, "
    # 石をとる
    capped_pos=capture(node_id, current_stone)
    if capped_pos.size==1 && no_of_breathing_points==0 && group_positions(node_id, false).size==1
      @ko_potential=[i, new_pos, capped_pos.first]
      puts "Ko potential #{@ko_potential}"
    end
    @amount_of_stones -= capped_pos.size
    show_board
  end

  # 座標を与えて、その座標にある石が属するグループの呼吸点の数を数える。
  # TODO: メソッド名は breath_point_amount とかの方がよい？
  # @param [Fixnum] x_pos; 0始まりのx座標
  # @param [Fixnum] y_pos; 0始まりのy座標
  # @param [String] stone; 黒なら"B"、白なら"W" 最初の呼び出しの時にはこの第二引数は不要
  # @return [Fixnum] 呼吸点の数
  def search(node_id, stone=nil)
    unless @nodes.keys.include?(node_id)
      # 盤の外なら0として返す。
      0   
    else
      pos = @nodes[node_id] # 黒か白か空点か
      if stone == nil # 最初の呼び出し
        @check = @check0.dup # チェック用の碁盤コピー
        if pos == "." || pos == nil # ナンセンス
          nil #TODO: 例外投げてもいいのかも。 
        else # posが"B"か"W"
          @check[node_id] = pos 
          # 隣接する点についてsearchを再帰的に呼び出して合計する。
          connected_nodes(node_id).map{|con_node_id| search(con_node_id, pos)}.sum
        end 
      else # 再帰呼出し
        if @check[node_id] != 0 # 0でなければ探索済ということ
           0
        else
          # TODO: posに関わらず@check[node_id]=pos を実行するので、ここで予め@check[node_id]=posを実行する方がDRYかも？
          case pos
          when "." # 空点 このときのみ呼吸点が増える
            @check[node_id] = pos
            1
          when stone # 同じ色の石 この場合さらにこの点の隣接点を起点に探索
            @check[node_id] = pos
            connected_nodes(node_id).map{|con_node_id| search(con_node_id, pos)}.sum
          else # 違う色の石
            @check[node_id] = pos
            0
          end
        end
      end
    end
  end

  # 今打った石によって、呼吸点が0になった石群を取り除く
  # @param [Fixnum] node_id 今打ったノードID
  # @param [String] stone 今打った石の色（"B"or"W"）
  # @param [True/False] estimate @board, @positionsを実際に操作せずに石をとれるかどうか確認する
  # @return [Array] 打ち上げられる石が存在するノードIDの配列
  def capture(node_id, stone, estimate: false)
    capped_stone_pos=[]
    # 隣接点についてそれぞれ確認
    connected_nodes(node_id).each do |con_node_id|
      next unless @nodes.keys.include?(con_node_id) && @nodes[con_node_id]==opposite(stone)
      next unless search(con_node_id)==0
      group_positions(con_node_id).each do |capped_node_id|
        unless estimate
          @nodes[capped_node_id] = "." 
          @positions.delete(capped_node_id)
          puts "#{opposite(stone)}@(#{con_node_id}) is captured."
        end 
        capped_stone_pos << con_node_id
      end 
    end 
    capped_stone_pos
  end


end


b = Board.new([[1,2],[1,5],[1,8],[2,3],[2,10],[3,4],[3,12],[4,5],[4,14],[5,6],
[6,7],[6,15],[7,8],[7,17],[8,9],[9,10],[9,18],[10,11],[11,12],[11,19],
[12,13],[13,14],[13,20],[14,15],[15,16],[16,17],[16,20],[17,18],[18,19],[19,20],
[21,22],[21,25],[21,28],[22,23],[22,30],[23,24],[23,32],[24,25],[24,34],[25,26],
[26,27],[26,35],[27,28],[27,37],[28,29],[29,30],[29,38],[30,31],[31,32],[31,39],
[32,33],[33,34],[33,40],[34,35],[35,36],[36,37],[36,40],[37,38],[38,39],[39,40],
[1,21],[2,22],[3,23],[4,24],[5,25],[6,26],[7,27],[8,28],[9,29],[10,30],
[11,31],[12,32],[13,33],[14,34],[15,35],[16,36],[17,37],[18,38],[19,39],[20,40]])
(1..40).each {|i| p "#{i}: #{b.connected_edges(i)}, #{b.connected_nodes(i)}" }

