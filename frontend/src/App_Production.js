import React, { 
  useState, 
  useEffect, 
  useCallback, 
  useMemo, 
  useRef,
  Suspense,
  lazy,
  startTransition
} from 'react';
import { 
  ErrorBoundary,
  useErrorHandler,
  withErrorBoundary 
} from 'react-error-boundary';
import { 
  QueryClient, 
  QueryClientProvider, 
  useQuery, 
  useMutation, 
  useQueryClient,
  useInfiniteQuery 
} from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { 
  createBrowserRouter, 
  RouterProvider, 
  Navigate,
  useNavigate,
  useParams,
  Outlet 
} from 'react-router-dom';
import { Helmet, HelmetProvider } from 'react-helmet-async';
import { toast, ToastContainer, Slide } from 'react-toastify';
import { Analytics } from '@vercel/analytics/react';
import { SpeedInsights } from '@vercel/speed-insights/react';

// Lazy loaded components for code splitting
const Dashboard = lazy(() => import('./components/Dashboard'));
const RoomView = lazy(() => import('./components/RoomView'));
const PollView = lazy(() => import('./components/PollView'));
const AdminPanel = lazy(() => import('./components/AdminPanel'));
const ReportsView = lazy(() => import('./components/ReportsView'));

// Performance monitoring
import './utils/performance';
import { reportWebVitals } from './utils/reportWebVitals';
import { ErrorFallback } from './components/ErrorFallback';
import { LoadingSpinner } from './components/LoadingSpinner';
import { OfflineIndicator } from './components/OfflineIndicator';
import { ServiceWorkerManager } from './utils/serviceWorker';

// Custom hooks
import { useWebSocket } from './hooks/useWebSocket';
import { usePerformanceMonitor } from './hooks/usePerformanceMonitor';
import { useNetworkStatus } from './hooks/useNetworkStatus';
import { useLocalStorage } from './hooks/useLocalStorage';
import { useDebounce } from './hooks/useDebounce';
import { useIntersectionObserver } from './hooks/useIntersectionObserver';

// Utils
import { api } from './utils/api';
import { cache } from './utils/cache';
import { logger } from './utils/logger';
import { metrics } from './utils/metrics';
import { security } from './utils/security';

// Styles
import './App.css';
import 'react-toastify/dist/ReactToastify.css';

// Global error tracking
window.addEventListener('error', (event) => {
  logger.error('Global error:', event.error);
  metrics.track('error.global', { 
    message: event.error?.message,
    filename: event.filename,
    lineno: event.lineno 
  });
});

window.addEventListener('unhandledrejection', (event) => {
  logger.error('Unhandled promise rejection:', event.reason);
  metrics.track('error.unhandled_promise', { reason: event.reason });
});

// React Query configuration
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      cacheTime: 1000 * 60 * 30, // 30 minutes
      retry: (failureCount, error) => {
        if (error?.status === 404) return false;
        return failureCount < 3;
      },
      retryDelay: attemptIndex => Math.min(1000 * 2 ** attemptIndex, 30000),
      refetchOnWindowFocus: false,
      refetchOnReconnect: 'always',
      suspense: false, // We'll handle loading states manually
    },
    mutations: {
      retry: 1,
      onError: (error) => {
        logger.error('Mutation error:', error);
        toast.error(`Operation failed: ${error.message}`);
      }
    }
  }
});

// Main App Component with all optimizations
const App = () => {
  // Performance monitoring
  const { trackMetric } = usePerformanceMonitor();
  const { isOnline, effectiveType } = useNetworkStatus();
  
  // Component state
  const [user, setUser] = useLocalStorage('supervote_user', null);
  const [theme, setTheme] = useLocalStorage('supervote_theme', 'light');
  const [lastActivity, setLastActivity] = useState(Date.now());
  
  // Refs for performance
  const appRef = useRef(null);
  const renderCountRef = useRef(0);
  
  // Track render count for performance
  renderCountRef.current += 1;
  
  useEffect(() => {
    trackMetric('app.render', { count: renderCountRef.current });
  }, [trackMetric]);
  
  // Activity tracking for session management
  useEffect(() => {
    const handleActivity = () => setLastActivity(Date.now());
    
    const events = ['mousedown', 'mousemove', 'keypress', 'scroll', 'touchstart'];
    events.forEach(event => {
      document.addEventListener(event, handleActivity, { passive: true });
    });
    
    return () => {
      events.forEach(event => {
        document.removeEventListener(event, handleActivity);
      });
    };
  }, []);
  
  // Session timeout (30 minutes of inactivity)
  useEffect(() => {
    const checkInactivity = () => {
      const now = Date.now();
      const thirtyMinutes = 30 * 60 * 1000;
      
      if (now - lastActivity > thirtyMinutes && user) {
        logger.info('Session expired due to inactivity');
        setUser(null);
        toast.info('Session expired due to inactivity');
      }
    };
    
    const interval = setInterval(checkInactivity, 60000); // Check every minute
    return () => clearInterval(interval);
  }, [lastActivity, user, setUser]);
  
  // Theme management
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    document.documentElement.className = theme;
  }, [theme]);
  
  // Performance optimization: Memoized router configuration
  const router = useMemo(() => createBrowserRouter([
    {
      path: '/',
      element: <Layout />,
      errorElement: <ErrorPage />,
      children: [
        {
          index: true,
          element: (
            <Suspense fallback={<LoadingSpinner />}>
              <Dashboard />
            </Suspense>
          )
        },
        {
          path: 'room/:roomId',
          element: (
            <Suspense fallback={<LoadingSpinner />}>
              <RoomView />
            </Suspense>
          )
        },
        {
          path: 'poll/:pollId',
          element: (
            <Suspense fallback={<LoadingSpinner />}>
              <PollView />
            </Suspense>
          )
        },
        {
          path: 'admin',
          element: (
            <Suspense fallback={<LoadingSpinner />}>
              <AdminPanel />
            </Suspense>
          )
        },
        {
          path: 'reports',
          element: (
            <Suspense fallback={<LoadingSpinner />}>
              <ReportsView />
            </Suspense>
          )
        }
      ]
    }
  ]), []);
  
  // Error boundary handler
  const handleError = useCallback((error, errorInfo) => {
    logger.error('App error boundary:', error, errorInfo);
    metrics.track('error.boundary', { 
      message: error.message,
      stack: error.stack,
      componentStack: errorInfo?.componentStack 
    });
  }, []);
  
  return (
    <HelmetProvider>
      <QueryClientProvider client={queryClient}>
        <ErrorBoundary
          FallbackComponent={ErrorFallback}
          onError={handleError}
          onReset={() => window.location.reload()}
        >
          <div ref={appRef} className="app" data-testid="app">
            <Helmet>
              <title>SUPERvote - State-of-the-art Polling</title>
              <meta name="description" content="Professional anonymous polling system with real-time results" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
              <meta name="theme-color" content="#3B82F6" />
              <link rel="manifest" href="/manifest.json" />
              <link rel="icon" href="/favicon.ico" />
              <link rel="apple-touch-icon" href="/logo192.png" />
            </Helmet>
            
            {/* Network status indicator */}
            <OfflineIndicator isOnline={isOnline} effectiveType={effectiveType} />
            
            {/* Main router */}
            <RouterProvider router={router} />
            
            {/* Toast notifications */}
            <ToastContainer
              position="top-right"
              autoClose={5000}
              hideProgressBar={false}
              newestOnTop
              closeOnClick
              rtl={false}
              pauseOnFocusLoss
              draggable
              pauseOnHover
              transition={Slide}
              theme={theme}
            />
            
            {/* Analytics */}
            <Analytics />
            <SpeedInsights />
            
            {/* Development tools */}
            {process.env.NODE_ENV === 'development' && (
              <ReactQueryDevtools initialIsOpen={false} />
            )}
          </div>
        </ErrorBoundary>
      </QueryClientProvider>
    </HelmetProvider>
  );
};

// Layout component with common functionality
const Layout = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  
  // WebSocket connection management
  const { 
    isConnected, 
    lastMessage, 
    sendMessage, 
    connectionState 
  } = useWebSocket({
    url: `${process.env.REACT_APP_BACKEND_URL?.replace('http', 'ws')}/api/ws`,
    reconnectAttempts: 5,
    reconnectInterval: 1000,
    onMessage: useCallback((message) => {
      logger.debug('WebSocket message received:', message);
      
      // Handle real-time updates
      switch (message.type) {
        case 'participant_joined':
        case 'participant_approved':
        case 'participant_denied':
          queryClient.invalidateQueries(['participants']);
          break;
        case 'poll_created':
        case 'poll_started':
        case 'poll_stopped':
          queryClient.invalidateQueries(['polls']);
          break;
        case 'vote_cast':
          queryClient.invalidateQueries(['poll-results']);
          break;
        case 'room_updated':
          queryClient.invalidateQueries(['room']);
          break;
        default:
          logger.debug('Unknown message type:', message.type);
      }
    }, [queryClient])
  });
  
  // Connection status indicator
  useEffect(() => {
    if (connectionState === 'connected') {
      toast.success('Connected to real-time updates');
    } else if (connectionState === 'disconnected') {
      toast.warning('Disconnected from real-time updates');
    } else if (connectionState === 'reconnecting') {
      toast.info('Reconnecting...');
    }
  }, [connectionState]);
  
  return (
    <>
      {/* Connection status bar */}
      {connectionState !== 'connected' && (
        <div className="connection-status-bar">
          <div className="container mx-auto px-4 py-2 text-center text-sm">
            {connectionState === 'connecting' && (
              <span className="text-yellow-600">Connecting to real-time updates...</span>
            )}
            {connectionState === 'reconnecting' && (
              <span className="text-orange-600">Reconnecting to real-time updates...</span>
            )}
            {connectionState === 'disconnected' && (
              <span className="text-red-600">
                Disconnected from real-time updates. Some features may not work properly.
              </span>
            )}
          </div>
        </div>
      )}
      
      {/* Main content */}
      <main className="main-content">
        <Outlet />
      </main>
    </>
  );
};

// Error page component
const ErrorPage = () => {
  const navigate = useNavigate();
  
  return (
    <div className="error-page">
      <div className="container mx-auto px-4 py-16 text-center">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          Oops! Something went wrong
        </h1>
        <p className="text-lg text-gray-600 mb-8">
          We apologize for the inconvenience. Please try again.
        </p>
        <div className="space-x-4">
          <button
            onClick={() => navigate(-1)}
            className="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            Go Back
          </button>
          <button
            onClick={() => navigate('/')}
            className="px-6 py-3 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition-colors"
          >
            Go Home
          </button>
        </div>
      </div>
    </div>
  );
};

// Service Worker registration
if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
  window.addEventListener('load', () => {
    ServiceWorkerManager.register('/sw.js')
      .then((registration) => {
        logger.info('SW registered: ', registration);
      })
      .catch((registrationError) => {
        logger.error('SW registration failed: ', registrationError);
      });
  });
}

// Web Vitals reporting
reportWebVitals((metric) => {
  logger.debug('Web Vital:', metric);
  metrics.track(`web_vital.${metric.name}`, {
    value: metric.value,
    id: metric.id,
    delta: metric.delta
  });
});

// Export with error boundary HOC
export default withErrorBoundary(App, {
  FallbackComponent: ErrorFallback,
  onError: (error, errorInfo) => {
    logger.error('App level error:', error, errorInfo);
    metrics.track('error.app_level', { 
      message: error.message,
      stack: error.stack 
    });
  }
});