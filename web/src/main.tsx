import React from 'react';import{createRoot}from'react-dom/client';import'./styles.css';import'./motion.css';import'./preview.css';import'./watch-native.css';import'./watch-only.css';import App from'./App';import DevicePreview from'./DevicePreview';
const Screen=location.pathname.includes('/device-preview')?DevicePreview:App;
createRoot(document.getElementById('root')!).render(<React.StrictMode><Screen/></React.StrictMode>);
