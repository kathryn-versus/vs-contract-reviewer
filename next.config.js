/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    serverComponentsExternalPackages: ['firebase-admin', 'googleapis'],
  },
};

module.exports = nextConfig;
