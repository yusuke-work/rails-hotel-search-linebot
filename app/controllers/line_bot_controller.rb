class LineBotController < ApplicationController
  # CSRF(クロスサイトリクエストフォージェリ)対策の無効化
  # protect_form_forgeryはCSRF対策のメソッド
  # LINEプラットフォームからのPOSTリクエスト先(callback)アクションではCSRF対策を無効化
  protect_from_forgery except: [:callback]

  # LINEからのPOSTリクエストのメッセージボディを取得して解析
  def callback
    # リクエストのメッセージボディを文字列で取得(メッセージボディにメッセージが入っている)
    body = request.body.read

    # POSTリクエストの署名を検証(ヘッダー参照)
    signature = request.env['HTTP_X_LINE_SIGNATURE']
    # チャネルと連携してPOSTリクエストのボディと署名を検証
    unless client.validate_signature(body, signature)
      #不正なリクエストだったらheadメソッドでbad_request(400)のステータスコードを返す
      return head :bad_request
    end

    # メッセージボディの要素を配列に変換してeventsに入れる
    events = client.parse_events_from(body)

    events.each do |event|
      # eventがLine::Bot::Event::Messageクラス(ユーザーがメッセージを送信したことを示すイベント)かどうか判断
      case event
      when Line::Bot::Event::Message
        # eventのtypeがtextつまりテキストメッセージか判断
        case event.type
        when Line::Bot::Event::MessageType::Text

          # search_and_create_messageは楽天APIと通信してメッセージを作成するメソッド
          # メッセージボディのtextキーにメッセージが入っている
          message = search_and_create_message(event.message['text'])
          # event(メッセージボディ)の応答トークンを取得
          # reply_messageで応答トークンとmessageを返信
          client.reply_message(event['replyToken'], message)
        end
      end
    end
    #正常を意味するステータスコード200を返す
    # head :ok
  end

  private

  # チャネルと連携するため
  # 環境変数のチャネルシークレットとチャネルアクセストークンでインスタンス化
  def client
    # LINE APIのLine::Bot::Clientクラスをインスタンス化することでメッセージの解析や返信などの機能を使うことができるようになる
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  # Railsと楽天APIを通信
  # 検索とメッセージ作成を行う
  # LINEアプリから送られたキーワード('text': "")がkeywordに入る
  def search_and_create_message(keyword)
    http_client = HTTPClient.new
    # APIのGETリクエスト先
    url = 'https://app.rakuten.co.jp/services/api/Travel/KeywordHotelSearch/20170426'
    # パラメータ指定
    query = {
      # 検索キーワード(LINEアプリから送られたキーワード=keyword)
      'keyword' => keyword,
      # アプリID
      'applicationId' => ENV['RAKUTEN_APPID'],
      # 取得件数
      'hits' => 5,
      # 取得量
      'responseType' => 'small',
      # 緯度経度タイプ
      'datumType' => 1,
      # 出力フォーマット
      'formatVersion' => 2
    }

    # getメソッドで指定したURLにGETリクエストしてそのレスポンスを取得してresponseに代入
    response = http_client.get(url, query)

    # parseメソッドでレスポンスボディのJSONをハッシュに変換して再代入
    # response["hotels"]のように簡単に各データにアクセスすることができる
    response = JSON.parse(response.body)
    
    # 検索結果にerrorのキーが有るかどうか
    if response.key?('error')
      text = "この検索条件に該当する宿泊施設が見つかりませんでした。\n条件を変えて再検索してください。"
      {

        # LINEに送るtypeはtext形式でtextは上記の文言(text)
        type: 'text',
        text: text
      }
    else
      {
        type: 'flex',
        altText: '宿泊検索の結果です。',
        contents: set_carousel(response['hotels'])
      }
    end
  end

  # カルーセルコンテナ(バブルコンテナの集まり)
  def set_carousel(hotels) # hotelsは楽天APIから受け取ったホテル情報の集まり
    # バブルコンテナの配列
    # 各ホテル情報(hotel[0]['hotelBasicInfo'])をset_bubbleに渡して作成されたバブルコンテナをpushでbubblesの末尾に追加
    bubbles = []
    hotels.each do |hotel|
      bubbles.push set_bubble(hotel[0]['hotelBasicInfo'])
    end
    {
      # カルーセルコンテナを宣言
      type: 'carousel',
      # バブルコンテナの配列であるbubblesを指定
      contents: bubbles
    }
  end

  # バブルコンテナ(単体コンテナ)
  def set_bubble(hotel) # hotelは楽天APIから受け取った各ホテル情報
    {
      type: 'bubble',
      hero: set_hero(hotel),
      body: set_body(hotel),
      footer: set_footer(hotel)
    }
  end


  # デザインしたJSONを元に各コンテナのヒーローブロック(ホテルの画像とそのリンク)
  def set_hero(hotel)
    {
      type: 'image',
      url: hotel['hotelImageUrl'],
      size: 'full',
      aspectRatio: '20:13',
      aspectMode: 'cover',
      action: {
        type: 'uri',
        uri:  hotel['hotelInformationUrl']
      }
    }
  end

  # デザインしたJSONを元に各コンテナのボディブロック(住所や料金)
  def set_body(hotel)
    {
      type: 'box',
      layout: 'vertical',
      contents: [
        {
          type: 'text',
          # ホテル名
          text: hotel['hotelName'],
          wrap: true,
          weight: 'bold',
          size: 'md'
        },
        {
          type: 'box',
          layout: 'vertical',
          margin: 'lg',
          spacing: 'sm',
          contents: [
            {
              type: 'box',
              layout: 'baseline',
              spacing: 'sm',
              contents: [
                {
                  type: 'text',
                  text: '住所',
                  color: '#aaaaaa',
                  size: 'sm',
                  flex: 1
                },
                {
                  type: 'text',
                  # ホテルの住所(都道府県+それ以下)
                  text: hotel['address1'] + hotel['address2'],
                  wrap: true,
                  color: '#666666',
                  size: 'sm',
                  flex: 5
                }
              ]
            },
            {
              type: 'box',
              layout: 'baseline',
              spacing: 'sm',
              contents: [
                {
                  type: 'text',
                  text: '料金',
                  color: '#aaaaaa',
                  size: 'sm',
                  flex: 1
                },
                {
                  type: 'text',
                  # 最安値料金を¥0,000〜というフォーマットで表示
                  text: '￥' + hotel['hotelMinCharge'].to_s(:delimited) + '〜',
                  wrap: true,
                  color: '#666666',
                  size: 'sm',
                  flex: 5
                }
              ]
            }
          ]
        }
      ]
    }
  end

  # デザインしたJSONを元に各コンテナのフッターブロック(電話番号や住所)
  def set_footer(hotel)
    {
      type: 'box',
      layout: 'vertical',
      spacing: 'sm',
      contents: [
        {
          type: 'button',
          style: 'link',
          height: 'sm',
          action: {
            type: 'uri',
            label: '電話する',
            # 電話番号
            uri: 'tel:' + hotel['telephoneNo']
          }
        },
        {
          type: 'button',
          style: 'link',
          height: 'sm',
          action: {
            type: 'uri',
            label: '地図を見る',
            # 住所(緯度と経度を取得して文字列に変換してGoogleマップのURLに結合)
            uri: 'https://www.google.com/maps?q=' + hotel['latitude'].to_s + ',' + hotel['longitude'].to_s
          }
        },
        {
          type: 'spacer',
          size: 'sm'
        }
      ],
      flex: 0
    }
  end
end
