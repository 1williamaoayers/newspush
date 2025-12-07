import { styleText } from 'node:util'

// Configuration
const CONFIG = {
  API_BASE_URL: process.env.SOURCE_URL || 'http://localhost:4399',
  FEISHU_WEBHOOK_URL:
    process.env.FEISHU_WEBHOOK_URL ||
    'https://www.feishu.cn/flow/api/trigger-webhook/e9eb3eb901b500ab55b2f44c50194268',
}

if (!CONFIG.FEISHU_WEBHOOK_URL) {
  console.error('Error: FEISHU_WEBHOOK_URL environment variable is required.')
  process.exit(1)
}

// Types
interface ApiResponse<T> {
  code: number
  message: string
  data: T
}

interface News60sData {
  date: string
  day_of_week: string
  lunar_date: string
  tip: string
  news: string[]
  link: string
}

interface HotItem {
  title?: string
  keyword?: string
  name?: string
  query?: string
  url?: string
  link?: string
  hotUrl?: string
  article_url?: string
}

interface HotData {
  data: HotItem[]
}

// Helpers
const fetchJson = async <T>(endpoint: string): Promise<T | null> => {
  try {
    const url = `${CONFIG.API_BASE_URL}${endpoint}`
    const response = await fetch(url)
    if (!response.ok) {
      console.error(`Failed to fetch ${url}: ${response.statusText}`)
      return null
    }
    const json = (await response.json()) as ApiResponse<T>
    if (json.code !== 200) {
      console.error(`API Error ${url}: ${json.message} (Code: ${json.code})`)
      return null
    }
    return json.data
  } catch (error) {
    console.error(`Network error fetching ${endpoint}:`, error)
    return null
  }
}

// Formatters
const format60sNews = (data: News60sData): string => {
  const { date, day_of_week, lunar_date, tip, news, link } = data
  const separator = '='.repeat(50)

  let message = `【每日新闻】${date} ${day_of_week} ${lunar_date}\n${separator}\n\n`

  if (tip) {
    message += `💡 ${tip}\n\n`
  }

  if (Array.isArray(news)) {
    news.forEach((item, index) => {
      message += `${index + 1}. ${item}\n\n`
    })
  }

  if (link) {
    message += `🔗 阅读原文: ${link}\n\n`
  }

  return message
}

const formatHotNews = (data: HotItem[], sourceName: string): string => {
  const separator = '='.repeat(50)
  let message = `【${sourceName} 热点】\n${separator}\n\n`

  data.forEach((item, index) => {
    const title = item.title || item.keyword || item.name || item.query || item.title
    const url = item.url || item.link || item.hotUrl || item.article_url

    if (title) {
      message += `${index + 1}. ${title}\n`
      if (url) {
        message += `   🔗 ${url}\n`
      }
      message += '\n'
    }
  })

  return message
}

// Main Logic
const main = async () => {
  console.log('Starting news push task...')

  // Fetch Data
  const [news60s, baiduHot, toutiaoHot, zhihuHot] = await Promise.all([
    fetchJson<News60sData>('/v2/60s'),
    fetchJson<HotItem[]>('/v2/baidu/hot'),
    fetchJson<HotItem[]>('/v2/toutiao'),
    fetchJson<HotItem[]>('/v2/zhihu'),
  ])

  let combinedMessage = ''

  // Format 60s News
  if (news60s) {
    combinedMessage += format60sNews(news60s)
  }

  // Format Hot News
  if (baiduHot) {
    combinedMessage += formatHotNews(baiduHot, '百度')
  }

  if (toutiaoHot) {
    combinedMessage += formatHotNews(toutiaoHot, '头条')
  }

  if (zhihuHot) {
    combinedMessage += formatHotNews(zhihuHot, '知乎')
  }

  if (!combinedMessage) {
    console.log('No news data fetched. Exiting.')
    return
  }

  // Add Footer
  combinedMessage += '='.repeat(50) + '\n'
  combinedMessage += '来源: https://github.com/vikiboss/60s\n'

  // Send to Feishu
  try {
    console.log('Sending to Feishu...')
    const payload = {
      msg_type: 'text',
      content: {
        text: combinedMessage,
      },
    }

    const response = await fetch(CONFIG.FEISHU_WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })

    const result = (await response.json()) as any

    if (result.code === 0 || result.StatusCode === 0 || result.status === 'success') {
      console.log('News pushed successfully!')
    } else {
      console.error('Feishu API Error:', result)
    }
  } catch (error) {
    console.error('Failed to send to Feishu:', error)
  }
}

main()
