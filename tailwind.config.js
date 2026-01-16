const colors = require('tailwindcss/colors')
module.exports = {
  mode: 'jit',
  purge: {
    // enabled: false,
    content: ['./app/**/*.html*', './app/**/*.vue']
  },
  darkMode: false, // or 'media' or 'class'
  important: true,
  theme: {
    screens: {
      xxl: '1920px',
      xl: {
        max: '1439px'
      },
      lg: {
        max: '1279px'
      },
      md: {
        max: '1023px'
      },
      sm: {
        max: '767px'
      }
      // 'sm': '640px',
      // 'md': '768px',
      // 'lg': '1024px',
      // 'xl': '1280px',
    },
    inset: {
      0: 0,
      '1/2': '50%',
      '-05': '-1rem'
    },
    colors: {
      transparent: 'transparent',
      current: 'currentColor',
      black: colors.black,
      white: colors.white,
      gray: colors.blueGray,
      red: colors.red,
      yellow: colors.yellow,
      orange: colors.orange,
      lime: colors.lime,
      green: colors.green,
      teal: colors.teal,
      cyan: colors.cyan,
      blue: colors.blue,
      pink: colors.pink,
      indigo: colors.indigo
    },
    extend: {
      fontSize: {
        '1vw': '1vw',
        '2vw': '2vw',
        '2.5vw': '2.5vw'
      },
      height: {
        screenContent: 'calc(100vh - 6rem)'
      },
      minHeight: {
        screenContent: 'calc(100vh - 6rem)'
      },
      backgroundOpacity: {
        10: '0.1',
        20: '0.2',
        95: '0.95'
      }
    }
  },
  variants: {
    extend: {}
  },
  plugins: []
}
