class LineBotController < ApplicationController
  protect_from_forgery except: [:callback]

  def callback
    body = request.body.read
    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      return head :bad_request
    end
    events = client.parse_events_from(body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          message = search_and_create_message(event.message['text'])
          client.reply_message(event['replyToken'], message)
        end
      end
    end
    head :ok
  end

  private

  def client
    # Line::Bot::Clientクラスをインスタンス化することでメッセージの解析や返信などの機能を使うことができるようになる
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def search_and_create_message(keyword)
    http_client = HTTPClient.new
    url = 'https://app.rakuten.co.jp/services/api/Travel/KeywordHotelSearch/20170426'
    query = {
      'keyword' => keyword,
      'applicationId' => ENV['RAKUTEN_APPID'],
      'hits' => 5,
      'responseType' => 'small',
      'datumType' => 1,
      'formatVersion' => 2
    }
    response = http_client.get(url, query)
    response = JSON.parse(response.body)
    
    if response.key?('error')
      text = "この検索条件に該当する宿泊施設が見つかりませんでした。\n条件を変えて再検索してください。"
      {
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
  def set_carousel(hotels) # hotelsは楽天APIから受け取ったホテル情報
    bubbles = []
    hotels.each do |hotel|
      bubbles.push set_bubble(hotel[0]['hotelBasicInfo'])
    end
    {
      type: 'carousel',
      contents: bubbles
    }
  end

  # バブルコンテナ(単体コンテナ)
  def set_bubble(hotel)
    {
      type: 'bubble',
      hero: set_hero(hotel),
      body: set_body(hotel),
      footer: set_footer(hotel)
    }
  end


  # 各コンテナのヒーローブロック(ホテルの画像とそのリンク)
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

  # 各コンテナのボディブロック(住所や料金)
  def set_body(hotel)
    {
      type: 'box',
      layout: 'vertical',
      contents: [
        {
          type: 'text',
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

  # 各コンテナのフッターブロック(電話番号や住所)
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
