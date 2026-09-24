package com.example.autonomouseye;

import android.content.Context;
import android.util.Log;

import info.mqtt.android.service.MqttAndroidClient;
import org.eclipse.paho.client.mqttv3.IMqttActionListener;
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken;
import org.eclipse.paho.client.mqttv3.IMqttToken;
import org.eclipse.paho.client.mqttv3.MqttCallbackExtended;
import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.eclipse.paho.client.mqttv3.MqttMessage;

import java.util.UUID;

public class MqttManager {

    private static final String TAG = "MqttManager";
    private static MqttManager instance;

    private final Context context;
    private final String brokerUrl;
    private final String clientId;
    private MqttAndroidClient client;
    private MqttListener listener;
    private boolean connecting = false;

    public interface MqttListener {
        void onConnected();
        void onDisconnected();
        void onMessageReceived(String topic, String payload);
        void onError(String error);
    }

    private MqttManager(Context context, String brokerUrl) {
        this.context = context.getApplicationContext();
        this.brokerUrl = brokerUrl;
        // clientId создаётся один раз и хранится всё время жизни приложения
        this.clientId = "Eye_" + UUID.randomUUID().toString().substring(0, 8);
        this.client = new MqttAndroidClient(this.context, brokerUrl, clientId);
    }

    public static synchronized MqttManager getInstance(Context context, String brokerUrl) {
        if (instance == null) {
            instance = new MqttManager(context, brokerUrl);
        }
        return instance;
    }

    public void setListener(MqttListener listener) {
        this.listener = listener;
        // Если уже подключены — сразу сообщаем
        if (isConnected() && listener != null) {
            listener.onConnected();
        }
    }

    public void connect(String username, String password) {
        if (isConnected() || connecting) {
            Log.d(TAG, "Already connected or connecting");
            return;
        }
        connecting = true;

        MqttConnectOptions options = new MqttConnectOptions();
        options.setAutomaticReconnect(false);   // отключаем встроенный reconnect
        options.setCleanSession(true);
        options.setConnectionTimeout(30);
        options.setKeepAliveInterval(60);
        if (username != null && !username.isEmpty()) {
            options.setUserName(username);
            options.setPassword(password.toCharArray());
        }

        client.setCallback(new MqttCallbackExtended() {
            @Override
            public void connectComplete(boolean reconnect, String serverURI) {
                Log.d(TAG, "Connected to " + serverURI);
                connecting = false;
                if (listener != null) listener.onConnected();
            }

            @Override
            public void connectionLost(Throwable cause) {
                Log.e(TAG, "Connection lost", cause);
                connecting = false;
                if (listener != null) listener.onDisconnected();

                // Пробуем переподключиться через 5 секунд
                new android.os.Handler(android.os.Looper.getMainLooper())
                        .postDelayed(() -> connect(username, password), 5000);
            }

            @Override
            public void messageArrived(String topic, MqttMessage message) {
                String payload = new String(message.getPayload());
                Log.d(TAG, "Message on " + topic + ": " + payload);
                if (listener != null) listener.onMessageReceived(topic, payload);
            }

            @Override
            public void deliveryComplete(IMqttDeliveryToken token) {
            }
        });

        try {
            client.connect(options, null, new IMqttActionListener() {
                @Override
                public void onSuccess(IMqttToken asyncActionToken) {
                    Log.d(TAG, "Connect success");
                    connecting = false;
                }

                @Override
                public void onFailure(IMqttToken asyncActionToken, Throwable exception) {
                    Log.e(TAG, "Connect failed", exception);
                    connecting = false;
                    if (listener != null)
                        listener.onError("Connect failed: " + exception.getMessage());
                }
            });
        } catch (Exception e) {
            connecting = false;
            Log.e(TAG, "Connect error", e);
            if (listener != null) listener.onError(e.getMessage());
        }
    }

    public void subscribe(String topic, int qos) {
        try {
            if (!isConnected()) return;
            client.subscribe(topic, qos, null, new IMqttActionListener() {
                @Override
                public void onSuccess(IMqttToken asyncActionToken) {
                    Log.d(TAG, "Subscribed to " + topic);
                }

                @Override
                public void onFailure(IMqttToken asyncActionToken, Throwable exception) {
                    Log.e(TAG, "Subscribe failed", exception);
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Subscribe error", e);
        }
    }

    public void publish(String topic, String payload, int qos, boolean retained) {
        try {
            if (!isConnected()) return;
            MqttMessage message = new MqttMessage(payload.getBytes());
            message.setQos(qos);
            message.setRetained(retained);
            client.publish(topic, message);
        } catch (Exception e) {
            Log.e(TAG, "Publish error", e);
        }
    }

    /** НЕ отключаем — иначе при перезапуске Activity будет новый клиент. */
    public void disconnect() {
        // оставляем намеренно пустым: пусть клиент живёт, пока приложение в памяти
    }

    public boolean isConnected() {
        return client != null && client.isConnected();
    }
}
