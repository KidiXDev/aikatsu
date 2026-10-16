import { defineConfig } from 'vitepress'

const base = '/aikatsu/'

export default defineConfig({
  base,
  title: 'Aikatsu',
  description: 'Watch anime, manage your sources, and build plugins for Aikatsu.',
  lang: 'en',
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: `${base}icon.svg` }]],
  themeConfig: {
    logo: '/icon.svg',
    siteTitle: 'Aikatsu docs',
    nav: [
      { text: 'Start here', link: '/guide/getting-started' },
      { text: 'Plugins', link: '/plugins/' },
      { text: 'For developers', link: '/developers/' }
    ],
    sidebar: [
      {
        text: 'Using Aikatsu',
        items: [
          { text: 'Getting started', link: '/guide/getting-started' },
          { text: 'Find something to watch', link: '/guide/discover-and-search' },
          { text: 'The video player', link: '/guide/player' },
          { text: 'Anime4K', link: '/guide/anime4k' },
          { text: 'Downloads and offline viewing', link: '/guide/downloads' },
          { text: 'History and settings', link: '/guide/settings' },
          { text: 'Troubleshooting', link: '/guide/troubleshooting' }
        ]
      },
      {
        text: 'Your plugins',
        items: [
          { text: 'How plugins work', link: '/plugins/' },
          { text: 'Add, update, or remove', link: '/plugins/managing-plugins' }
        ]
      },
      {
        text: 'For developers',
        items: [
          { text: 'Start building', link: '/developers/' },
          { text: 'Your first plugin', link: '/developers/first-plugin' },
          { text: 'Plugin function contract', link: '/developers/plugin-contract' },
          { text: 'Host API reference', link: '/developers/host-api' },
          { text: 'Test and debug a plugin', link: '/developers/testing' },
          { text: 'Publish a plugin repo', link: '/developers/publishing' },
          { text: 'Build the app', link: '/developers/building-aikatsu' },
          { text: 'Work on these docs', link: '/developers/docs-site' }
        ]
      }
    ],
    socialLinks: [{ icon: 'github', link: 'https://github.com/KidiXDev/aikatsu' }],
    search: { provider: 'local' },
    outline: [2, 3],
    editLink: {
      pattern: 'https://github.com/KidiXDev/aikatsu/edit/main/docs/:path',
      text: 'Help improve this page'
    },
    footer: {
      message: 'Aikatsu is free software, licensed under GPL-3.0-only.',
      copyright: 'Copyright © 2026 Aikatsu'
    }
  }
})
